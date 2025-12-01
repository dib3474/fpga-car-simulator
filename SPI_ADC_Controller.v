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
    reg [2:0] channel_addr; // Address to send (Next Channel)
    reg [15:0] shift_in;    // Data received
    
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
                    spi_mosi <= 0; // Bit 15 (X)
                    state <= S_TRANS;
                end

                S_TRANS: begin
                    // Read MISO on Rising Edge
                    if (sck_enable_rise) begin
                        shift_in <= {shift_in[14:0], spi_miso};
                    end
                    
                    // Write MOSI on Falling Edge
                    if (sck_enable_fall) begin
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 16) begin // [수정] 16번째 비트까지 다 읽고 종료 (기존 15 -> 16)
                            state <= S_DONE;
                        end else begin
                            // Send Address at Bit 13, 12, 11 (Cycle 2, 3, 4)
                            // bit_cnt becomes 1, 2, 3...
                            // We want to set MOSI for the NEXT rising edge.
                            // bit_cnt 0 (Fall 1) -> Set Bit 14 (X)
                            // bit_cnt 1 (Fall 2) -> Set Bit 13 (ADD2)
                            // bit_cnt 2 (Fall 3) -> Set Bit 12 (ADD1)
                            // bit_cnt 3 (Fall 4) -> Set Bit 11 (ADD0)
                            
                            case (bit_cnt + 1)
                                3: spi_mosi <= channel_addr[2]; // Bit 13 (ADD2)
                                4: spi_mosi <= channel_addr[1]; // Bit 12 (ADD1)
                                5: spi_mosi <= channel_addr[0]; // Bit 11 (ADD0)
                                default: spi_mosi <= 0;
                            endcase
                        end
                    end
                end

                S_DONE: begin
                    if (sck_enable_fall) begin
                        spi_cs_n <= 1;
                        
                        // Pipeline: Data received is for the PREVIOUS channel.
                        // If we just sent CH1 request (channel_addr=1), we received CH0 data.
                        if (channel_addr == 1) adc_accel <= shift_in[11:4]; // Upper 8 bits
                        else if (channel_addr == 0) adc_cds <= shift_in[11:4];
                        
                        // Toggle Channel for next frame
                        if (channel_addr == 0) channel_addr <= 1;
                        else channel_addr <= 0;
                        
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule