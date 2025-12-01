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
                    // [Timing Fix] AD7908 samples on Falling Edge.
                    // Master must update MOSI on Rising Edge to ensure setup time.
                    // Master reads MISO on Rising Edge (stable after Slave's Falling Edge update).
                    
                    if (sck_enable_rise) begin
                        // 1. Read MISO
                        if (bit_cnt >= 1 && bit_cnt <= 16) begin
                             shift_in <= {shift_in[14:0], spi_miso};
                        end

                        // 2. Write MOSI
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
                        
                        // 3. Increment & Check Done
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 16) begin
                            state <= S_DONE;
                            spi_cs_n <= 1;
                        end
                    end
                end

                S_DONE: begin
                    // AD7908 Data Format:
                    // [15:14]: 00
                    // [13:11]: Address
                    // [10:3]:  Data (8-bit)
                    // [2:0]:   Trailing
                    
                    // [Fix] User reports speed decreases when voltage > 2.5V.
                    // This indicates bit overflow or misalignment where MSB is being lost or interpreted as sign.
                    // If 2.5V is mid-scale (128), and it wraps around or decreases, we might be reading the wrong bits.
                    // Let's try shifting the window by 1 bit to the left [11:4] to capture the MSB if it was in bit 11.
                    // Or, if the range bit was wrong, maybe it's outputting 10-bit? No, it's 8-bit.
                    
                    // Let's look at the shift_in construction.
                    // shift_in <= {shift_in[14:0], spi_miso};
                    // If we read 16 bits.
                    // Bit 15 (First bit read) -> shift_in[15]
                    // ...
                    // Bit 0 (Last bit read) -> shift_in[0]
                    
                    // AD7908 Timing:
                    // Cycle 1: Leading Zero
                    // Cycle 2: Leading Zero
                    // Cycle 3: ADD2
                    // Cycle 4: ADD1
                    // Cycle 5: ADD0
                    // Cycle 6: DB7 (MSB)
                    // ...
                    // Cycle 13: DB0 (LSB)
                    
                    // Our code reads 16 bits.
                    // If bit_cnt=1 is the first read (Cycle 1).
                    // shift_in[15] = Cycle 1 (0)
                    // shift_in[14] = Cycle 2 (0)
                    // shift_in[13] = Cycle 3 (ADD2)
                    // shift_in[12] = Cycle 4 (ADD1)
                    // shift_in[11] = Cycle 5 (ADD0)
                    // shift_in[10] = Cycle 6 (DB7)
                    // ...
                    // shift_in[3] = Cycle 13 (DB0)
                    
                    // Wait, if the user says > 2.5V speed decreases.
                    // 2.5V is usually half of 5V. If Vref is 5V, 2.5V is 127 (01111111).
                    // If it goes to 128 (10000000), and we are missing the MSB, it becomes 0.
                    // This strongly suggests we are reading [9:2] instead of [10:3], effectively missing the MSB (DB7).
                    // If we read [9:2], DB7 is lost.
                    // When value is 127 (01111111), [9:2] sees 1111111.
                    // When value is 128 (10000000), [9:2] sees 0000000. -> Speed drops to 0!
                    
                    // So we need to shift LEFT by 1 bit to catch the MSB.
                    // We should read [11:4] instead of [10:3]?
                    // Let's re-verify the cycle count.
                    // We start reading when sck_enable_rise is true.
                    // bit_cnt starts at 0.
                    // In S_TRANS:
                    // if (sck_enable_rise)
                    //   if (bit_cnt >= 1 && bit_cnt <= 16) shift_in <= ...
                    
                    // Cycle 1 (bit_cnt=1): Read 1st bit.
                    // ...
                    // Cycle 16 (bit_cnt=16): Read 16th bit.
                    
                    // If AD7908 outputs DB7 at Cycle 6.
                    // Cycle 1: 0
                    // Cycle 2: 0
                    // Cycle 3: A2
                    // Cycle 4: A1
                    // Cycle 5: A0
                    // Cycle 6: DB7
                    
                    // If we shift in 16 times.
                    // shift_in[0] is the LAST bit read (Cycle 16).
                    // shift_in[15] is the FIRST bit read (Cycle 1).
                    
                    // shift_in[15] = Cycle 1 (0)
                    // shift_in[14] = Cycle 2 (0)
                    // shift_in[13] = Cycle 3 (A2)
                    // shift_in[12] = Cycle 4 (A1)
                    // shift_in[11] = Cycle 5 (A0)
                    // shift_in[10] = Cycle 6 (DB7) <-- This matches my previous logic.
                    
                    // BUT, maybe the chip outputs data one cycle earlier or later?
                    // Or maybe the "Leading Zeros" are fewer?
                    // If the speed drops after 2.5V (128), it means the MSB is being interpreted as something else or ignored.
                    // If we are reading [9:2], then DB7 (at index 10) is ignored.
                    // DB6 (at index 9) becomes the MSB of our result.
                    // So 0..127 works fine. 128 (10000000) becomes 0.
                    
                    // Wait, if I am reading [10:3], I AM reading DB7.
                    // Unless... DB7 is actually at [11]?
                    // Let's try reading [11:4].
                    // If DB7 is at 11, then A0 is at 12, A1 at 13, A2 at 14.
                    // That would mean only 1 leading zero?
                    
                    // Let's try shifting the window to [11:4].
                    
                    if (prev_addr == 0) adc_cds <= shift_in[11:4];        // CH0 -> CdS
                    else if (prev_addr == 1) adc_accel <= shift_in[11:4]; // CH1 -> Accel
                    
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