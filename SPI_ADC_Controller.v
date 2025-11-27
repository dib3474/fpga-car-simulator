module SPI_ADC_Controller (
    input clk, 
    input rst,
    
    // SPI ���� ��
    output reg spi_sck, 
    output reg spi_cs_n, 
    output reg spi_mosi, 
    input spi_miso,
    
    // �� ���Ⱑ �ٽ� ������! (����� 2������ ��)
    output reg [7:0] adc_accel = 0,  // �Ǽ� ��
    output reg [7:0] adc_cds = 0     // ���� ��
);

    reg [7:0] clk_div = 0; 
    reg [4:0] bit_cnt = 0; 
    reg [15:0] shift_reg = 0; 
    reg sck_toggled = 0;
    reg [2:0] ch_addr = 0; 
    reg [2:0] state = 0; // FSM ����

    // 1MHz SPI Clock
    always @(posedge clk or posedge rst) begin
        if(rst) begin clk_div<=0; sck_toggled<=0; end 
        else begin if(clk_div>=24) begin clk_div<=0; sck_toggled<=~sck_toggled; end else clk_div<=clk_div+1; end
    end

    // 2ä�� ���� �б� ����
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_cs_n<=1; spi_sck<=0; spi_mosi<=0; bit_cnt<=0;
            adc_accel<=0; adc_cds<=0; state<=0; ch_addr<=0;
        end else if (clk_div==0) begin
            case(state)
                0: begin ch_addr<=0; state<=1; end // CH0 �غ� (�Ǽ�)
                3: begin ch_addr<=1; state<=4; end // CH1 �غ� (CDS)
                
                1, 4: begin // ��� ��
                    if(spi_cs_n) begin spi_cs_n<=0; bit_cnt<=0; end 
                    else begin
                        if(sck_toggled) begin spi_sck<=1; shift_reg<={shift_reg[14:0],spi_miso}; end 
                        else begin 
                            spi_sck<=0; 
                            // MCP3202 Protocol: Start(1), SGL(1), ODD/SIGN(CH), MSBF(1)
                            if(bit_cnt==0) spi_mosi<=1;      // Start Bit
                            else if(bit_cnt==1) spi_mosi<=1; // SGL/DIFF (Single Ended)
                            else if(bit_cnt==2) spi_mosi<=ch_addr[0]; // ODD/SIGN (Channel)
                            else if(bit_cnt==3) spi_mosi<=1; // MSBF (MSB First)
                            else spi_mosi<=0;
                            
                            bit_cnt<=bit_cnt+1; 
                        end
                        if(bit_cnt>16) begin 
                            spi_cs_n<=1; 
                            if(state==1) state<=2; else state<=5; 
                        end
                    end
                end
                
                2: begin adc_accel<=shift_reg[11:4]; state<=3; end // �Ǽ� ����
                5: begin adc_cds<=shift_reg[11:4]; state<=0; end   // CDS ����
            endcase
        end
    end
endmodule