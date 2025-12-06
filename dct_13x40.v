// dct_13x40.v - compute 13 MFCCs from 40 log-mel inputs
module dct_13x40(
  input clk, input rst_n,
  input start, // pulse to begin reading logs
  input signed [15:0] log_in, // Q6.10
  input log_valid,
  output reg signed [15:0] mfcc_out, // Q6.10
  output reg [7:0] mfcc_index,
  output reg mfcc_valid,
  output reg done
);
  localparam MEL_BANDS = 40;
  localparam MFCC_COEFFS = 13;

  reg signed [15:0] dct_rom [0:MFCC_COEFFS*MEL_BANDS-1];
  initial $readmemh("roms/dct.hex", dct_rom);

  reg signed [15:0] logs [0:MEL_BANDS-1];
  reg [5:0] recv_cnt;
  reg processing;
  integer n,i;
  reg signed [47:0] acc;
  reg signed [31:0] prod;

  always @(posedge clk) begin
    if (!rst_n) begin
      recv_cnt <= 0; mfcc_valid <= 0; mfcc_out <= 0; mfcc_index <= 0; done <= 0; processing <= 0;
      for (i=0;i<MEL_BANDS;i=i+1) logs[i] <= 0;
    end else begin
      mfcc_valid <= 0;
      if (start) begin
        recv_cnt <= 0; done <= 0;
      end
      if (log_valid) begin
        logs[recv_cnt] <= log_in;
        recv_cnt <= recv_cnt + 1;
        if (recv_cnt == MEL_BANDS-1) begin
          processing <= 1;
          mfcc_index <= 0;
        end
      end
      if (processing) begin
        acc = 0;
        for (n=0; n<MEL_BANDS; n=n+1) begin
          prod = $signed(logs[n]) * $signed(dct_rom[mfcc_index*MEL_BANDS + n]); // Q6.10 * Q1.15 -> Q7.25
          acc = acc + (prod >>> 15);
        end
        // reduce to Q6.10 16-bit with saturation
        // acc is wide; extract bits [25:10] as Q6.10 (simple truncation)
        mfcc_out <= acc[25:10];
        mfcc_valid <= 1;
        if (mfcc_index == MFCC_COEFFS-1) begin
          processing <= 0; done <= 1;
        end else mfcc_index <= mfcc_index + 1;
      end
    end
  end
endmodule
