`timescale 1ns/1ps

module tb_mfcc();

    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz clock

    reg rst_n = 0;
    reg signed [15:0] sample_in = 0;
    reg sample_valid = 0;
    reg start_clip = 0;

    wire mfcc_valid;
    wire signed [15:0] mfcc_data;
    wire [7:0] mfcc_frame_index;
    wire [7:0] mfcc_coeff_index;

    // DUT
    mfcc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .start_clip(start_clip),
        .mfcc_valid(mfcc_valid),
        .mfcc_data(mfcc_data),
        .mfcc_frame_index(mfcc_frame_index),
        .mfcc_coeff_index(mfcc_coeff_index)
    );

    // 16k 16-bit audio samples
    reg signed [15:0] frame_mem [0:15999];
    integer i;
    integer fd_check;
    initial begin
      fd_check = $fopen("python/audio_samples.hex","r");
      if (fd_check == 0) begin
        $display("+++ ERROR: Cannot open python/audio_samples.hex (check path & name).");
      end else begin
        $display("+++ OK: file python/audio_samples.hex opened (fd=%0d).", fd_check);
        $fclose(fd_check);
      end
    end
    
 
    
    initial begin
        $display("Loading audio samples...");
        $readmemh("python/audio_samples.hex", frame_mem);   // <---- YOUR FILE HERE

        // Apply reset
        rst_n = 0;
        sample_valid = 0;
        start_clip = 0;
        #200;
        rst_n = 1;
        #100;

        // Start 1-second clip
        @(posedge clk);
        start_clip = 1;
        @(posedge clk);
        start_clip = 0;

        // Feed 16000 samples
        for (i = 0; i < 16000; i = i + 1) begin
            @(posedge clk);
            sample_in    = frame_mem[i];
            sample_valid = 1;
        end

        // stop feeding samples
        @(posedge clk);
        sample_valid = 0;

        // Wait for MFCC output
        repeat (200000) @(posedge clk);

        $finish;
    end

    // OPTIONAL: Save MFCCs to file
    integer mfcc_fd;
    initial mfcc_fd = $fopen("mfcc_output.txt", "w");

    always @(posedge clk) begin
        if (mfcc_valid)
            $fwrite(mfcc_fd, "%0d %0d %0d\n", 
                mfcc_frame_index,
                mfcc_coeff_index,
                mfcc_data);
    end

endmodule
