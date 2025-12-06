module windowing #(
  parameter FRAME_SIZE = 2048,
  parameter HOP = 512
)(
  input  wire clk,
  input  wire rst_n,
  input  wire signed [15:0] sample_in,
  input  wire               sample_valid,
  input  wire               start_frame, // Session enable: must be high for the duration of the clip
  output reg                win_valid,
  output reg signed [15:0]  win_sample,
  output reg                frame_done
);

  // Shift register (holds the 2048 most recent samples)
  reg signed [15:0] shift_reg [0:FRAME_SIZE-1]; 
  reg [31:0] sample_count; // Tracks total samples received in the session
  reg [10:0] read_idx;     // Index for reading out the current 2048-sample window
  reg sending;            // FSM state: 1 when a frame is currently being streamed
  
  // Window ROM (loaded from roms/window.hex)
  reg signed [15:0] window_rom [0:FRAME_SIZE-1];
  initial $readmemh("roms/window.hex", window_rom);
  
  integer i;
  reg signed [31:0] mult_tmp;

  always @(posedge clk) begin
    if (!rst_n) begin
      sample_count <= 0;
      sending <= 0;
      win_valid <= 0;
      frame_done <= 0;
      read_idx <= 0;
    end else begin
      frame_done <= 0;
      win_valid <= 0;

      // 1. Shift in new samples continuously
      if (sample_valid && start_frame) begin
         // Shift all current samples one position (0 becomes 1, 1 becomes 2, etc.)
         for (i = 0; i < FRAME_SIZE-1; i = i + 1) begin
             shift_reg[i] <= shift_reg[i+1];
         end
         // Place the new sample at the end (index 2047)
         shift_reg[FRAME_SIZE-1] <= sample_in;
         
         sample_count <= sample_count + 1;
      end

      // 2. Frame Trigger Logic
      // Check if we are ready to start streaming a new frame
      if (sample_valid && start_frame && !sending) begin
          if (sample_count < FRAME_SIZE) begin
              // Not enough samples yet (ignore until the first 2048 are filled)
          end
          else begin
             // Trigger frame output every HOP (512) samples after the initial FRAME_SIZE (2048)
             if ( ((sample_count - FRAME_SIZE + 1) % HOP) == 0) begin
                 sending <= 1; 
                 read_idx <= 0; 
             end
          end
      end

      // 3. Send Windowed Data Stream
      if (sending) begin
          // Multiply sample by window coefficient (Q1.15 * Q1.15 -> shift 15)
          mult_tmp = $signed(shift_reg[read_idx]) * $signed(window_rom[read_idx]);
          win_sample <= mult_tmp >>> 15;
          win_valid <= 1;
          
          if (read_idx == FRAME_SIZE - 1) begin
              // Finished streaming the current frame
              sending <= 0;
              frame_done <= 1;
              read_idx <= 0;
          end else begin
              read_idx <= read_idx + 1;
          end
      end
    end
  end
endmodule