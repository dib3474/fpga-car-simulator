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

    // FSM for ADC128S022
    reg [1:0] state;
    reg [4:0] bit_cnt;
    reg [2:0] channel_addr; // 000(CH0) or 001(CH1)
    reg [11:0] shift_in;    // 12-bit Data
    
    localparam S_IDLE = 0;
    localparam S_TRANS = 1;
    localparam S_DONE = 2;

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
                        state <= S_TRANS;
                        spi_cs_n <= 0; // CS Low to start
                        bit_cnt <= 0;
                    end
                end
                
                S_TRANS: begin
                    // Write MOSI on Falling Edge (ADC samples on Rising)
                    if (sck_enable_fall) begin
                        // ADC128S022 Protocol:
                        // Bit 15, 14: Don't Care
                        // Bit 13: Addr 2
                        // Bit 12: Addr 1
                        // Bit 11: Addr 0
                        // Bit 10-0: Don't Care
                        
                        // We are sending 16 bits (cnt 0 to 15)
                        // cnt 0 -> Bit 15
                        // cnt 1 -> Bit 14
                        // cnt 2 -> Bit 13 (A2)
                        // cnt 3 -> Bit 12 (A1)
                        // cnt 4 -> Bit 11 (A0)
                        
                        case (bit_cnt)
                            2: spi_mosi <= 0; // A2
                            3: spi_mosi <= 0; // A1
                            4: spi_mosi <= channel_addr[0]; // A0 (0 for CH0, 1 for CH1)
                            default: spi_mosi <= 0;
                        endcase
                        
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 16) begin
                            state <= S_DONE;
                            spi_cs_n <= 1;
                        end
                    end
                    
                    // Read MISO on Rising Edge (ADC outputs on Falling)
                    if (sck_enable_rise) begin
                        // Data comes out:
                        // Cycle 0-3: Z/Zeros
                        // Cycle 4: D11
                        // ...
                        // Cycle 15: D0
                        if (bit_cnt >= 1 && bit_cnt <= 16) begin
                             shift_in <= {shift_in[10:0], spi_miso};
                        end
                    end
                end

                S_DONE: begin
                    // Update Values
                    // shift_in contains the 12-bit result
                    if (channel_addr == 0) adc_cds <= shift_in[11:4];   // CH0 -> CDS
                    else adc_accel <= shift_in[11:4];                   // CH1 -> Accel
                    
                    // Toggle Channel for next read
                    if (channel_addr == 0) channel_addr <= 1;
                    else channel_addr <= 0;
                    
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
