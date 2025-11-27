module SPI_ADC_Controller (
    input clk, 
    input rst,
    
    // SPI 물리 핀
    output reg spi_sck, 
    output reg spi_cs_n, 
    output reg spi_mosi, 
    input spi_miso,
    
    // ★ 여기가 핵심 변경점! (출력이 2개여야 함)
    output reg [7:0] adc_accel,  // 악셀 값
    output reg [7:0] adc_cds     // 조도 값
);

    reg [7:0] clk_div; 
    reg [4:0] bit_cnt; 
    reg [15:0] shift_reg; 
    reg sck_toggled;
    reg [2:0] ch_addr; 
    reg [2:0] state; // FSM 상태

    // 1MHz SPI Clock
    always @(posedge clk or posedge rst) begin
        if(rst) begin clk_div<=0; sck_toggled<=0; end 
        else begin if(clk_div>=24) begin clk_div<=0; sck_toggled<=~sck_toggled; end else clk_div<=clk_div+1; end
    end

    // 2채널 순차 읽기 로직
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_cs_n<=1; spi_sck<=0; spi_mosi<=0; bit_cnt<=0;
            adc_accel<=0; adc_cds<=0; state<=0; ch_addr<=0;
        end else if (clk_div==0) begin
            case(state)
                0: begin ch_addr<=0; state<=1; end // CH0 준비 (악셀)
                3: begin ch_addr<=1; state<=4; end // CH1 준비 (CDS)
                
                1, 4: begin // 통신 중
                    if(spi_cs_n) begin spi_cs_n<=0; bit_cnt<=0; end 
                    else begin
                        if(sck_toggled) begin spi_sck<=1; shift_reg<={shift_reg[14:0],spi_miso}; end 
                        else begin 
                            spi_sck<=0; 
                            // 주소 비트 전송 (3,4,5번째 비트)
                            if(bit_cnt==2) spi_mosi<=0; 
                            else if(bit_cnt==3) spi_mosi<=0; 
                            else if(bit_cnt==4) spi_mosi<=ch_addr[0]; 
                            bit_cnt<=bit_cnt+1; 
                        end
                        if(bit_cnt>16) begin 
                            spi_cs_n<=1; 
                            if(state==1) state<=2; else state<=5; 
                        end
                    end
                end
                
                2: begin adc_accel<=shift_reg[11:4]; state<=3; end // 악셀 저장
                5: begin adc_cds<=shift_reg[11:4]; state<=0; end   // CDS 저장
            endcase
        end
    end
endmodule