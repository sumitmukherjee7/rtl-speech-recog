// fft_ip_wrap.v
// Verilog wrapper that instantiates the generated VHDL xfft_0 IP (AXI-Stream).
// Matches the ports in the provided xfft_0.vhd (C_M_AXIS_DATA_TDATA_WIDTH = 32).

module fft_ip_wrap (
    input  wire           clk,
    input  wire           rst_n,        // not connected to FFT (IP was generated with no aresetn)
    // simple input from windowing
    input  wire signed [15:0] win_sample,
    input  wire               win_valid,
    input  wire               frame_done,

    // outputs to magnitude stage
    output wire signed [31:0] fft_real,   // sign-extended to 32
    output wire signed [31:0] fft_imag,   // sign-extended to 32
    output wire               fft_valid,
    output wire               fft_last
);

    // ----- AXI-Stream input packing (s_axis_data_tdata is 32 bits) -----
    // s_axis_data_tdata := { imag[15:0], real[15:0] }
    wire [31:0] s_axis_data_tdata;
    wire        s_axis_data_tvalid;
    wire        s_axis_data_tlast;

    assign s_axis_data_tdata  = {16'h0000, win_sample}; // imag = 0, real = sample
    assign s_axis_data_tvalid = win_valid;
    assign s_axis_data_tlast  = frame_done;

    // ----- AXI-Stream config (not using runtime config) -----
    wire [7:0]  s_axis_config_tdata  = 8'd0;
    wire        s_axis_config_tvalid = 1'b0;
    wire        s_axis_config_tready;

    // ----- FFT outputs -----
    wire [31:0] m_axis_data_tdata;
    wire [7:0]  m_axis_data_tuser;
    wire        m_axis_data_tvalid;
    wire        m_axis_data_tready;
    wire        m_axis_data_tlast;

    wire [7:0]  m_axis_status_tdata;
    wire        m_axis_status_tvalid;
    wire        m_axis_status_tready;

    // events (not used)
    wire event_frame_started;
    wire event_tlast_unexpected;
    wire event_tlast_missing;
    wire event_status_channel_halt;
    wire event_data_in_channel_halt;
    wire event_data_out_channel_halt;

    // Tie ready signals high so IP can stream out in simulation
    assign m_axis_data_tready   = 1'b1;
    assign m_axis_status_tready = 1'b1;

    // Instantiate the VHDL IP (entity name: xfft_0)
    // port names MUST match those in xfft_0.vhd (you provided).
    xfft_0 fft_core (
        .aclk(clk),
        .s_axis_config_tdata (s_axis_config_tdata),
        .s_axis_config_tvalid(s_axis_config_tvalid),
        .s_axis_config_tready(s_axis_config_tready),
        .s_axis_data_tdata   (s_axis_data_tdata),
        .s_axis_data_tvalid  (s_axis_data_tvalid),
        .s_axis_data_tready  ( /* unused */ ),
        .s_axis_data_tlast   (s_axis_data_tlast),
        .m_axis_data_tdata   (m_axis_data_tdata),
        .m_axis_data_tuser   (m_axis_data_tuser),
        .m_axis_data_tvalid  (m_axis_data_tvalid),
        .m_axis_data_tready  (m_axis_data_tready),
        .m_axis_data_tlast   (m_axis_data_tlast),
        .m_axis_status_tdata (m_axis_status_tdata),
        .m_axis_status_tvalid(m_axis_status_tvalid),
        .m_axis_status_tready(m_axis_status_tready),
        .event_frame_started (event_frame_started),
        .event_tlast_unexpected(event_tlast_unexpected),
        .event_tlast_missing (event_tlast_missing),
        .event_status_channel_halt(event_status_channel_halt),
        .event_data_in_channel_halt(event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt)
    );

    // ----- Unpack m_axis_data_tdata (32-bit) into real & imag (16-bit each) -----
    // Assumption: lower 16 bits = real (signed), upper 16 bits = imag (signed)
    wire signed [15:0] fft_real_16 = m_axis_data_tdata[15:0];
    wire signed [15:0] fft_imag_16 = m_axis_data_tdata[31:16];

    // Sign-extend to 32 bits for downstream processing
    assign fft_real  = {{16{fft_real_16[15]}}, fft_real_16};
    assign fft_imag  = {{16{fft_imag_16[15]}}, fft_imag_16};

    assign fft_valid = m_axis_data_tvalid;
    assign fft_last  = m_axis_data_tlast;

endmodule
