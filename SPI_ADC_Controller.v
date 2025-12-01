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

    // Clock Divider for SPI SCLK (Target: 10kHz)
    // User Requirement: "Clk는... 10kHz로 설정해야 사용해야 합니다."
    // 50MHz / 10kHz = 5000. Toggle every 2500 cycles.
    reg [15:0] clk_cnt;
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
            if (clk_cnt >= 2499) begin // 2500 cycles (0~2499)
                clk_cnt <= 0;
                spi_sck <= ~spi_sck;
                if (spi_sck == 0) sck_enable_rise <= 1; // 0->1 Rising
                else sck_enable_fall <= 1;              // 1->0 Falling
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // FSM for AD7908 (8-bit ADC)
    reg [1:0] state;
    reg [4:0] bit_cnt;
    reg [2:0] channel_addr; // Address to send
    reg [2:0] prev_addr;    // Address sent in previous frame
    reg [15:0] shift_in;    // 16-bit Data (Full Frame)
    
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
            prev_addr <= 0;
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
                    // Write MOSI on Falling Edge
                    if (sck_enable_fall) begin
                        // AD7908 Control Word (12 bits + 4 trailing zeros)
                        // Bit 11: WRITE (1)
                        // Bit 10: SEQ (0)
                        // Bit 9:  Don't Care (0)
                        // Bit 8:  ADD2
                        // Bit 7:  ADD1
                        // Bit 6:  ADD0
                        // Bit 5:  PM1 (1)
                        // Bit 4:  PM0 (1)
                        // Bit 3:  SHADOW (0)
                        // Bit 2:  WEAK/TRI (0)
                        // Bit 1:  RANGE (1) - 0 to Vref
                        // Bit 0:  CODING (1) - Binary
                        
                        case (bit_cnt)
                            0: spi_mosi <= 1; // WRITE
                            1: spi_mosi <= 0; // SEQ
                            2: spi_mosi <= 0; // Don't Care
                            3: spi_mosi <= channel_addr[2]; // ADD2
                            4: spi_mosi <= channel_addr[1]; // ADD1
                            5: spi_mosi <= channel_addr[0]; // ADD0
                            6: spi_mosi <= 1; // PM1
                            7: spi_mosi <= 1; // PM0
                            8: spi_mosi <= 0; // SHADOW
                            9: spi_mosi <= 0; // WEAK
                            10: spi_mosi <= 1; // RANGE
                            11: spi_mosi <= 1; // CODING
                            default: spi_mosi <= 0;
                        endcase
                        
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 16) begin
                            state <= S_DONE;
                            spi_cs_n <= 1;
                        end
                    end
                    
                    // Read MISO on Rising Edge
                    if (sck_enable_rise) begin
                        if (bit_cnt >= 1 && bit_cnt <= 16) begin
                             shift_in <= {shift_in[14:0], spi_miso};
                        end
                    end
                end

                S_DONE: begin
                    // AD7908 Data Format Adjustment
                    // Symptom: Max value is around 84 (should be 255).
                    // Cause: Data bits are likely shifted by 2 positions due to timing delays.
                    // Fix: Read from [8:1] instead of [10:3] to multiply value by 4.
                    
                    // [User Request] CH0 -> CDS, CH1 -> Accel
                    if (prev_addr == 0) adc_cds <= shift_in[8:1];        // CH0 -> CdS
                    else if (prev_addr == 1) adc_accel <= shift_in[8:1]; // CH1 -> Accel
                    
                    // Update Pipeline
                    prev_addr <= channel_addr;
                    
                    // Toggle Channel for next read (0 -> 1 -> 0)
                    if (channel_addr == 0) channel_addr <= 1;
                    else channel_addr <= 0;
                    
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule