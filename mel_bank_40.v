// mel_bank_40.v
// Reads FFT magnitudes for bins 0..1024 and produces 40 mel energies.
// mel_weights.hex must contain 40 * 1025 Q1.15 weights in row-major order.

module mel_bank_40(
  input wire clk, input wire rst_n,
  input wire start,               // pulse to start accumulation for a frame
  input wire [31:0] mag_in,
  input wire mag_valid,
  output reg signed [47:0] mel_out, // one mel band per mel_valid
  output reg [5:0] mel_index,       // 0..39
  output reg mel_valid,
  output reg done
);
  localparam FFT_BINS = 1025;
  localparam MEL_BANDS = 40;
  reg signed [15:0] mel_rom [0:(MEL_BANDS*FFT_BINS)-1];
  initial $readmemh("roms/mel_weights.hex", mel_rom);

  reg [9:0] bin_idx;
  reg [5:0] band_idx;
  reg signed [47:0] acc;
  reg accumulating;

  integer rom_addr;
  reg signed [31:0] weight_ext;
  reg signed [63:0] prod;

  always @(posedge clk) begin
    if (!rst_n) begin
      mel_valid <= 0; mel_out <= 0; mel_index <= 0; done <= 0;
      bin_idx <= 0; band_idx <= 0; acc <= 0; accumulating <= 0;
    end else begin
      mel_valid <= 0;
      if (start && !accumulating) begin
        band_idx <= 0;
        bin_idx <= 0;
        acc <= 0;
        accumulating <= 1;
        done <= 0;
      end
      if (accumulating && mag_valid) begin
        // read weight
        rom_addr = band_idx * FFT_BINS + bin_idx;
        weight_ext = {{16{mel_rom[rom_addr][15]}}, mel_rom[rom_addr]}; // sign-extend
        prod = $signed(mag_in) * $signed(weight_ext); // 32x32 -> 64
        // align Q: mag_in might be in some Q, weight in Q1.15 -> shift 15
        acc <= acc + (prod >>> 15);
        if (bin_idx == FFT_BINS-1) begin
          // finish band
          mel_out <= acc;
          mel_index <= band_idx;
          mel_valid <= 1;
          acc <= 0;
          bin_idx <= 0;
          if (band_idx == MEL_BANDS-1) begin
            done <= 1;
            accumulating <= 0;
          end else begin
            band_idx <= band_idx + 1;
          end
        end else begin
          bin_idx <= bin_idx + 1;
        end
      end
    end
  end
endmodule
