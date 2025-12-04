module LCD_Module (
    input clk, input rst, 
    input engine_on,        // ���� �õ� ����
    input is_off,           // [�߰�] ���� ���� OFF ���� ��ȣ
    input [31:0] odometer, input [7:0] fuel, input is_side_brake,
    output reg lcd_rs = 0, output reg lcd_rw = 0, output reg lcd_e = 0, output reg [7:0] lcd_data = 0
);
    parameter [5:0] S_DELAY_POW=0, S_INIT_1=1, S_INIT_2=2, S_INIT_3=3, S_FUNC_SET=4, S_DISP_OFF=5, 
                    S_CLR_DISP=6, S_ENTRY_MODE=7, S_DISP_ON=8, S_IDLE=9, S_LINE1_CMD=10, S_LINE1_WR=11, 
                    S_LINE2_CMD=12, S_LINE2_WR=13;
    reg [5:0] state = 0; 
    reg [19:0] cnt_delay = 0; 
    reg [19:0] wait_time = 0; 
    reg [4:0] char_idx = 0;
    reg [7:0] line1_buf [0:15]; 
    reg [7:0] line2_buf [0:15];
    
    // Engine Start Animation Logic
    reg [27:0] engine_start_timer = 0;
    reg prev_engine_on = 0;
    reg show_engine_on_msg = 0;
    
    // Key On Animation Logic
    reg [27:0] key_on_timer = 0;
    reg prev_is_off = 1;
    reg show_key_on_msg = 0;

    function [7:0] digit2ascii; input [3:0] d; begin if(d<10) digit2ascii=d+8'h30; else digit2ascii=8'h20; end endfunction

    // Detect Engine Start Edge & Key On Edge
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            engine_start_timer <= 0;
            prev_engine_on <= 0;
            show_engine_on_msg <= 0;
            
            key_on_timer <= 0;
            prev_is_off <= 1;
            show_key_on_msg <= 0;
        end else begin
            // Engine On Logic
            prev_engine_on <= engine_on;
            if (!engine_on) begin
                show_engine_on_msg <= 0;
                engine_start_timer <= 0;
            end else if (engine_on && !prev_engine_on) begin
                engine_start_timer <= 50_000_000; // 1 sec
                show_engine_on_msg <= 1;
            end else if (engine_start_timer > 0) begin
                engine_start_timer <= engine_start_timer - 1;
                if (engine_start_timer == 1) show_engine_on_msg <= 0;
            end
            
            // Key On Logic
            prev_is_off <= is_off;
            if (is_off) begin
                show_key_on_msg <= 0;
                key_on_timer <= 0;
            end else if (!is_off && prev_is_off) begin
                key_on_timer <= 50_000_000; // 1 sec
                show_key_on_msg <= 1;
            end else if (key_on_timer > 0) begin
                key_on_timer <= key_on_timer - 1;
                if (key_on_timer == 1) show_key_on_msg <= 0;
            end
        end
    end

    // [�ٽ� ����] ȭ�� ��� ���� ����
    always @(posedge clk) begin
        // 1. [�ֿ켱] ���� OFF ���¸� ȭ���� �������� ä�� (����� ȿ��)
        if (is_off) begin
            line1_buf[0]=" "; line1_buf[1]=" "; line1_buf[2]=" "; line1_buf[3]=" ";
            line1_buf[4]=" "; line1_buf[5]=" "; line1_buf[6]=" "; line1_buf[7]=" ";
            line1_buf[8]=" "; line1_buf[9]=" "; line1_buf[10]=" "; line1_buf[11]=" ";
            line1_buf[12]=" "; line1_buf[13]=" "; line1_buf[14]=" "; line1_buf[15]=" ";

            line2_buf[0]=" "; line2_buf[1]=" "; line2_buf[2]=" "; line2_buf[3]=" ";
            line2_buf[4]=" "; line2_buf[5]=" "; line2_buf[6]=" "; line2_buf[7]=" ";
            line2_buf[8]=" "; line2_buf[9]=" "; line2_buf[10]=" "; line2_buf[11]=" ";
            line2_buf[12]=" "; line2_buf[13]=" "; line2_buf[14]=" "; line2_buf[15]=" ";
        end 
        // 2. Engine On Message (Priority High)
        else if (show_engine_on_msg) begin
            line1_buf[0]=" "; line1_buf[1]=" "; line1_buf[2]=" "; line1_buf[3]="E";
            line1_buf[4]="N"; line1_buf[5]="G"; line1_buf[6]="I"; line1_buf[7]="N";
            line1_buf[8]="E"; line1_buf[9]=" "; line1_buf[10]="O"; line1_buf[11]="N";
            line1_buf[12]="!"; line1_buf[13]=" "; line1_buf[14]=" "; line1_buf[15]=" ";

            line2_buf[0]=" "; line2_buf[1]=" "; line2_buf[2]=" "; line2_buf[3]=" ";
            line2_buf[4]=" "; line2_buf[5]=" "; line2_buf[6]=" "; line2_buf[7]=" ";
            line2_buf[8]=" "; line2_buf[9]=" "; line2_buf[10]=" "; line2_buf[11]=" ";
            line2_buf[12]=" "; line2_buf[13]=" "; line2_buf[14]=" "; line2_buf[15]=" ";
        end 
        // 3. Key On Message
        else if (show_key_on_msg) begin
            line1_buf[0]=" "; line1_buf[1]=" "; line1_buf[2]=" "; line1_buf[3]=" ";
            line1_buf[4]="K"; line1_buf[5]="E"; line1_buf[6]="Y"; line1_buf[7]=" ";
            line1_buf[8]="O"; line1_buf[9]="N"; line1_buf[10]=" "; line1_buf[11]=" ";
            line1_buf[12]=" "; line1_buf[13]=" "; line1_buf[14]=" "; line1_buf[15]=" ";

            line2_buf[0]=" "; line2_buf[1]=" "; line2_buf[2]=" "; line2_buf[3]=" ";
            line2_buf[4]=" "; line2_buf[5]=" "; line2_buf[6]=" "; line2_buf[7]=" ";
            line2_buf[8]=" "; line2_buf[9]=" "; line2_buf[10]=" "; line2_buf[11]=" ";
            line2_buf[12]=" "; line2_buf[13]=" "; line2_buf[14]=" "; line2_buf[15]=" ";
        end
        // 4. Default (ODO/Fuel)
        else begin
            line1_buf[0]="O"; line1_buf[1]="D"; line1_buf[2]="O"; line1_buf[3]=":"; line1_buf[4]=" ";
            line1_buf[5]=digit2ascii((odometer/10000)%10); line1_buf[6]=digit2ascii((odometer/1000)%10);
            line1_buf[7]=digit2ascii((odometer/100)%10); line1_buf[8]=digit2ascii((odometer/10)%10);
            line1_buf[9]=digit2ascii(odometer%10); line1_buf[10]=" "; line1_buf[11]="k"; line1_buf[12]="m";
            line1_buf[13]=" "; line1_buf[14]=" "; line1_buf[15]=" ";

            if(is_side_brake) begin
                line2_buf[0]=" "; line2_buf[1]=" "; line2_buf[2]=" "; line2_buf[3]="S";
                line2_buf[4]="I"; line2_buf[5]="D"; line2_buf[6]="E"; line2_buf[7]=" ";
                line2_buf[8]="O"; line2_buf[9]="N"; line2_buf[10]="!"; line2_buf[11]=" ";
                line2_buf[12]=" "; line2_buf[13]=" "; line2_buf[14]=" "; line2_buf[15]=" ";
            end else begin
                line2_buf[0]=" "; line2_buf[1]="F"; line2_buf[2]="U"; line2_buf[3]="E";
                line2_buf[4]="L"; line2_buf[5]=":"; line2_buf[6]=" "; 
                if(fuel>=100) line2_buf[7]="1"; else line2_buf[7]=" ";
                line2_buf[8]=digit2ascii((fuel/10)%10); line2_buf[9]=digit2ascii(fuel%10);
                line2_buf[10]=" "; line2_buf[11]="%"; line2_buf[12]=" ";
                if(fuel<15) begin line2_buf[13]="!"; line2_buf[14]="!"; end else begin line2_buf[13]=" "; line2_buf[14]=" "; end
                line2_buf[15]=" ";
            end
        end
    end

    // FSM (�״�� ����)
    always @(posedge clk or posedge rst) begin
        if(rst) begin state<=S_DELAY_POW; cnt_delay<=0; char_idx<=0; lcd_e<=0; lcd_rs<=0; lcd_rw<=0; lcd_data<=0; wait_time<=2_000_000; end
        else begin
            if(cnt_delay<wait_time) begin
                cnt_delay<=cnt_delay+1;
                if(state!=S_DELAY_POW && cnt_delay==5000) lcd_e<=1; else if(cnt_delay==15000) lcd_e<=0;
            end else begin
                cnt_delay<=0;
                case(state)
                    S_DELAY_POW: begin state<=S_INIT_1; wait_time<=250_000; end
                    S_INIT_1: begin lcd_rs<=0; lcd_data<=8'h30; state<=S_INIT_2; wait_time<=10_000; end
                    S_INIT_2: begin lcd_rs<=0; lcd_data<=8'h30; state<=S_INIT_3; wait_time<=5_000; end
                    S_INIT_3: begin lcd_rs<=0; lcd_data<=8'h30; state<=S_FUNC_SET; wait_time<=5_000; end
                    S_FUNC_SET: begin lcd_rs<=0; lcd_data<=8'h38; state<=S_DISP_OFF; wait_time<=5_000; end
                    S_DISP_OFF: begin lcd_rs<=0; lcd_data<=8'h08; state<=S_CLR_DISP; wait_time<=100_000; end 
                    S_CLR_DISP: begin lcd_rs<=0; lcd_data<=8'h01; state<=S_ENTRY_MODE; wait_time<=100_000; end
                    S_ENTRY_MODE: begin lcd_rs<=0; lcd_data<=8'h06; state<=S_DISP_ON; wait_time<=5_000; end
                    S_DISP_ON: begin lcd_rs<=0; lcd_data<=8'h0C; state<=S_IDLE; wait_time<=50_000; end
                    S_IDLE: begin state<=S_LINE1_CMD; wait_time<=50_000; end
                    S_LINE1_CMD: begin lcd_rs<=0; lcd_data<=8'h80; char_idx<=0; state<=S_LINE1_WR; wait_time<=20_000; end
                    S_LINE1_WR: begin lcd_rs<=1; lcd_data<=line1_buf[char_idx]; if(char_idx<15) begin char_idx<=char_idx+1; state<=S_LINE1_WR; end else state<=S_LINE2_CMD; wait_time<=20_000; end
                    S_LINE2_CMD: begin lcd_rs<=0; lcd_data<=8'hC0; char_idx<=0; state<=S_LINE2_WR; wait_time<=20_000; end
                    S_LINE2_WR: begin lcd_rs<=1; lcd_data<=line2_buf[char_idx]; if(char_idx<15) begin char_idx<=char_idx+1; state<=S_LINE2_WR; end else state<=S_IDLE; wait_time<=20_000; end
                endcase
            end
        end
    end
endmodule