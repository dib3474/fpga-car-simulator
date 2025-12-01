module SPI_ADC_Controller (
    input clk, 
    input rst,
    
    // SPI Interface
    output reg spi_sck, 
    output reg spi_cs_n, 
    output reg spi_mosi, 
    input spi_miso,
    
    // ADC Values
    output reg [7:0] adc_accel = 0,  // CH0
    output reg [7:0] adc_cds = 0     // CH1
);

    // Clock Divider for SPI SCLK (Target: ~1MHz)
    // 50MHz / 50 = 1MHz. Toggle every 25 cycles.
    reg [7:0] clk_cnt;
    reg sck_enable_rise; 
    reg sck_enable_fall; 
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt <= 0;
            spi_sck <= 0;
            sck_enable_rise <= 0;
            sck_enable_fall <= 0;
        end else begin
            sck_enable_rise <= 0;
            sck_enable_fall <= 0;
            if (clk_cnt >= 24) begin // 25 cycles (0~24)
                clk_cnt <= 0;
                spi_sck <= ~spi_sck;
                if (spi_sck == 0) sck_enable_rise <= 1; // 0->1 Rising
                else sck_enable_fall <= 1;              // 1->0 Falling
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // FSM
    reg [2:0] state;
    reg [4:0] bit_cnt;
    reg channel_addr; // 1 bit for MCP3202 (0:CH0, 1:CH1)
    reg [11:0] shift_in; // 12-bit Data
    
    localparam S_IDLE = 0;
    localparam S_START = 1;
    localparam S_TRANS = 2;
    localparam S_DONE = 3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_cs_n <= 1;
            spi_mosi <= 0;
            state <= S_IDLE;
            bit_cnt <= 0;
            channel_addr <= 0; 
            adc_accel <= 0;
            adc_cds <= 0;
            shift_in <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    spi_cs_n <= 1;
                    if (sck_enable_fall) begin 
                        state <= S_START;
                    end
                end
                
                S_START: begin
                    spi_cs_n <= 0; 
                    bit_cnt <= 0;
                    spi_mosi <= 1; // Start Bit (MCP3202)
                    state <= S_TRANS;
                end

                S_TRANS: begin
                    // Read MISO on Rising Edge
                    if (sck_enable_rise) begin
                        // MCP3202: Null bit at Cycle 5, Data B11..B0 at Cycle 6..17
                        if (bit_cnt >= 5) begin
                            shift_in <= {shift_in[10:0], spi_miso};
                        end
                    end
                    
                    // Write MOSI on Falling Edge
                    if (sck_enable_fall) begin
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 17) begin // Total 17 Cycles
                            state <= S_DONE;
                            spi_cs_n <= 1;
                        end else begin
                            // MCP3202 Control Bits
                            // Cycle 1: Start (Sent in S_START)
                            // Cycle 2: SGL/DIFF (1)
                            // Cycle 3: ODD/SIGN (Channel)
                            // Cycle 4: MSBF (1)
                            
                            case (bit_cnt)
                                0: spi_mosi <= 1; // SGL (for Cycle 2)
                                1: spi_mosi <= channel_addr; // ODD (for Cycle 3)
                                2: spi_mosi <= 1; // MSBF (for Cycle 4)
                                default: spi_mosi <= 0;
                            endcase
                        end
                    end
                end

                S_DONE: begin
                    // MCP3202 is NOT pipelined. Data corresponds to the command just sent.
                    // [Correction] Based on symptoms: CH0 is CDS, CH1 is Accel.
                    if (channel_addr == 0) adc_cds <= shift_in[11:4];   // CH0 -> CDS
                    else adc_accel <= shift_in[11:4];                   // CH1 -> Accel
                    
                    // Toggle Channel
                    channel_addr <= ~channel_addr;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
