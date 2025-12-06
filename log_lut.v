// log_lut.v — fully synthesizable version
module log_lut #(
    parameter LUT_BITS = 12,         // LUT size = 4096
    parameter IN_WIDTH = 48          // mel energy input
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [IN_WIDTH-1:0] mel_in,
    input  wire                     start,
    output reg  signed [15:0]       log_out,
    output reg                      valid,
    output reg                      done
);

    localparam LUT_SIZE = (1 << LUT_BITS);

    // LUT memory
    reg signed [15:0] lut [0:LUT_SIZE-1];
    initial $readmemh("roms/log_lut.hex", lut);

    // internal registers
    reg processing;
    reg [LUT_BITS-1:0] idx;

    integer i;

    // MSB detector (priority encoder)
    reg [5:0] msb_pos;
    always @(*) begin
        msb_pos = 0;
        for (i = IN_WIDTH-1; i >= 0; i = i - 1) begin
            if (mel_in[i] == 1'b1)
                msb_pos = i[5:0];
        end
    end

    // main FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            log_out    <= 0;
            valid      <= 0;
            done       <= 0;
            processing <= 0;
        end
        else begin
            valid <= 0;
            done  <= 0;

            if (start && !processing) begin
                processing <= 1;

                // If mel energy <= 0 → log(0) = very small → use lut[0]
                if (mel_in <= 0) begin
                    idx = 0;
                end
                else begin
                    // Normalize value to LUT range (0..4095)
                    if (msb_pos > (LUT_BITS-1))
                        idx = mel_in >> (msb_pos - (LUT_BITS-1));
                    else
                        idx = mel_in[ (LUT_BITS-1):0 ];
                end

                // read LUT
                log_out <= lut[idx];
                valid   <= 1;
                done    <= 1;
                processing <= 0;
            end
        end
    end

endmodule
