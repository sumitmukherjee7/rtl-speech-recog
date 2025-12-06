// mfcc_top.v - top-level orchestrator for 1s clip -> 32 x 13 MFCCs
module mfcc_top(
  input clk, input rst_n,
  input signed [15:0] sample_in,
  input sample_valid,
  input start_clip, // start capturing 1s clip (now a pulse)
  // output: stream frames of 13 coeffs, each with index and valid
  output wire mfcc_valid,
  output wire signed [15:0] mfcc_data,
  output wire [7:0] mfcc_frame_index, // 0..31 (time index)
  output wire [7:0] mfcc_coeff_index  // 0..12 (freq index)
);
  
  // --- 1. Control Logic for Continuous Recording (NEW) ---
  // 'recording_active' latches the start_clip pulse and remains high until the last MFCC is produced.
  reg recording_active;
  
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        recording_active <= 1'b0;
    else if(start_clip) 
        recording_active <= 1'b1; // Latch high when clip starts
    // Turn off when the final MFCC coefficient (index 12) of the final frame (index 31) is valid
    else if(mfcc_frame_index == 8'd31 && mfcc_coeff_index == 8'd12 && mfcc_valid) 
        recording_active <= 1'b0;
  end
  

  // --- 2. Windowing Stage ---
  // instantiate windowing (captures full 2048 sample frame and streams windowed samples)
  wire win_valid;
  wire signed [15:0] win_sample;
  wire frame_done;
  
  windowing #(.FRAME_SIZE(2048), .HOP(512)) u_win(
    .clk(clk), .rst_n(rst_n),
    .sample_in(sample_in), .sample_valid(sample_valid),
    .start_frame(recording_active), // **MODIFIED to use recording_active**
    .win_valid(win_valid), .win_sample(win_sample),
    .frame_done(frame_done)
  );

// --- 3. FFT → Magnitude Stages (Unchanged) ---
wire [31:0] fft_real;
wire [31:0] fft_imag;
wire        fft_valid;
wire        fft_last;

wire [31:0] fft_mag;
wire        fft_mag_valid;
wire        fft_done;

fft_ip_wrap u_fft (
    .clk(clk),
    .rst_n(rst_n),
    .win_sample(win_sample),
    .win_valid(win_valid),
    .frame_done(frame_done),
    .fft_valid(fft_valid),
    .fft_real(fft_real),
    .fft_imag(fft_imag),
    .fft_last(fft_last)
);

magnitude_approx u_mag (
    .clk(clk),
    .rst_n(rst_n),
    .real_in(fft_real),
    .imag_in(fft_imag),
    .in_valid(fft_valid),
    .in_last(fft_last),
    .mag_out(fft_mag),
    .mag_valid(fft_mag_valid),
    .frame_done(fft_done)
);


  // --- 4. Mel Bank, Log LUT, and DCT Stages (Unchanged) ---
  // mel bank
  wire signed [47:0] mel_out;
  wire [5:0] mel_index;
  wire mel_valid;
  wire mel_done;
  mel_bank_40 u_mel(
    .clk(clk), .rst_n(rst_n),
    .start(fft_done), .mag_in(fft_mag), .mag_valid(fft_mag_valid),
    .mel_out(mel_out), .mel_index(mel_index), .mel_valid(mel_valid), .done(mel_done)
  );

  // log LUT: for each mel band we get log value
  wire signed [15:0] log_out;
  wire log_valid;
  wire log_done;
  log_lut u_log(
    .clk(clk), .rst_n(rst_n),
    .mel_in(mel_out), .start(mel_valid),
    .log_out(log_out), .valid(log_valid), .done(log_done)
  );

  // DCT: we need to feed the 40 logs for each frame and get 13 MFCCs back.
  wire signed [15:0] mfcc_out_w;
  wire [7:0] mfcc_idx_w;
  wire mfcc_valid_w;
  wire dct_done;
  dct_13x40 u_dct(
    .clk(clk), .rst_n(rst_n),
    .start(log_done), .log_in(log_out), .log_valid(log_valid),
    .mfcc_out(mfcc_out_w), .mfcc_index(mfcc_idx_w), .mfcc_valid(mfcc_valid_w), .done(dct_done)
  );

  // --- 5. Output FSM and Indexing (Original, but now functional) ---
  // This logic correctly streams the 13 MFCCs from the DCT and increments the frame counter.
  reg [7:0] frame_counter;
  reg out_valid_r;
  reg signed [15:0] out_data_r;
  reg [7:0] out_frame_idx_r;
  reg [7:0] out_coeff_idx_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      frame_counter <= 0;
      out_valid_r <= 0;
    end else begin
      out_valid_r <= 0;
      // dct_done is the end of the *stream* of 13 coeffs for one frame. 
      // The frame counter is updated inside the mfcc_valid_w block for synchronous output.

      if (mfcc_valid_w) begin
        // stream output
        out_valid_r <= 1;
        out_data_r <= mfcc_out_w;
        out_coeff_idx_r <= mfcc_idx_w;
        out_frame_idx_r <= frame_counter;
        
        // when coeff_idx == 12 (last), increment frame_counter for the next frame
        if (mfcc_idx_w == 8'd12) begin
          // Only increment if we haven't reached the max (31+1=32 frames)
          if (frame_counter < 8'd31) 
            frame_counter <= frame_counter + 1;
        end
      end
    end
  end

  assign mfcc_valid = out_valid_r;
  assign mfcc_data = out_data_r;
  assign mfcc_frame_index = out_frame_idx_r;
  assign mfcc_coeff_index = out_coeff_idx_r;

endmodule