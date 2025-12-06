module Display_Unit (
    input clk, 
    input rst,              
    input tick_scan, 
    input obd_mode_sw,      // 0: Normal, 1: OBD
    input [13:0] rpm, 
    input [7:0] speed, 
    input [7:0] fuel, 
    input [7:0] temp, 
    input [3:0] gear_char,  // 3:P, 6:r, 9:n, 12:d
    
    // 8-Digit 7-Segment
    output reg [7:0] seg_data = 0, 
    output reg [7:0] seg_com = 0,

    // 1-Digit 7-Segment
    output reg [7:0] seg_1_data = 0
);
    reg [15:0] left_val = 0, right_val = 0; 
    reg [2:0] scan_idx = 0; 
    reg [3:0] hex_digit = 0;

    // --- Leading Zero Blanking 함수 ---
    function [15:0] to_bcd4_blank;
        input [15:0] value;
        integer temp_val;
        integer thousands, hundreds, tens, ones;
        begin
            temp_val = value;
            if (temp_val > 9999) temp_val = 9999;
            
            thousands = temp_val / 1000;
            temp_val = temp_val % 1000;
            hundreds = temp_val / 100;
            temp_val = temp_val % 100;
            tens = temp_val / 10;
            ones = temp_val % 10;

            if (thousands == 0) begin
                thousands = 4'hF;
                if (hundreds == 0) begin
                    hundreds = 4'hF;
                    if (tens == 0) tens = 4'hF; 
                end
            end
            to_bcd4_blank = {thousands[3:0], hundreds[3:0], tens[3:0], ones[3:0]};
        end
    endfunction

    // --- [수정] 통합 디코더 (숫자 + 기어 문자) ---
    // Active High (1=ON), a=LSB 패턴 적용
    function [7:0] encode_digit;
        input [3:0] digit;
        begin
            case (digit)
                // 숫자 0~9
                4'h0: encode_digit = 8'b0011_1111; 
                4'h1: encode_digit = 8'b0000_0110;
                4'h2: encode_digit = 8'b0101_1011;
                4'h3: encode_digit = 8'b0100_1111;
                4'h4: encode_digit = 8'b0110_0110;
                4'h5: encode_digit = 8'b0110_1101;
                4'h6: encode_digit = 8'b0111_1101;
                4'h7: encode_digit = 8'b0000_0111;
                4'h8: encode_digit = 8'b0111_1111;
                4'h9: encode_digit = 8'b0110_1111;
                
                // [추가] 기어 문자 (P, r, n, d) - 10,11,12,13에 매핑
                4'd10: encode_digit = 8'b0111_0011; // P (a,b,e,f,g)
                4'd11: encode_digit = 8'b0101_0000; // r (e,g)
                4'd12: encode_digit = 8'b0101_0100; // n (c,e,g)
                4'd13: encode_digit = 8'b0101_1110; // d (b,c,d,e,g)

                // Blank
                4'hF: encode_digit = 8'b0000_0000;
                default: encode_digit = 8'b0000_0000;
            endcase
        end
    endfunction

    // --- 1. Data Selection (모드 선택) ---
    always @(*) begin
        // [공통] 왼쪽: RPM
        left_val = to_bcd4_blank({2'b0, rpm});
        
        if (obd_mode_sw) begin 
            // [OBD 모드] 오른쪽: 엔진 온도
            right_val = to_bcd4_blank({8'b0, temp});
        end else begin 
            // [일반 모드] 오른쪽: 속도
            right_val = to_bcd4_blank({8'b0, speed});
        end
    end

    // --- 2. Scan Timer ---
    always @(posedge clk or posedge rst) begin
        if (rst) scan_idx <= 0;
        else if (tick_scan) scan_idx <= scan_idx + 1;
    end

    // --- 3. 8-Digit Output ---
    always @(*) begin
        if (rst) begin
            seg_com = 8'hFF;
            seg_data = 8'h00; 
        end else begin
            seg_com = 8'hFF;
            seg_com[scan_idx] = 0; // Active Low Common

            case (scan_idx)
                // Right Value
                0: hex_digit = right_val[3:0];
                1: hex_digit = right_val[7:4];
                2: hex_digit = right_val[11:8]; 
                3: hex_digit = right_val[15:12];
                // Left Value
                4: hex_digit = left_val[3:0];
                5: hex_digit = left_val[7:4];
                6: hex_digit = left_val[11:8]; 
                7: hex_digit = left_val[15:12];
            endcase
            
            seg_data = encode_digit(hex_digit);
        end
    end

    // --- 4. 1-Digit Output (기어 표시) ---
    // 모드 상관없이 항상 기어 표시
    // 입력값(3,6,9,12)을 디코더 인덱스(10,11,12,13)로 변환하여 출력
    reg [3:0] gear_idx;
    always @(*) begin
        if (rst) begin
            seg_1_data = 8'h00;
            gear_idx = 4'hF;
        end else begin
            case (gear_char)
                4'd3:  gear_idx = 4'd10; // P
                4'd6:  gear_idx = 4'd11; // r
                4'd9:  gear_idx = 4'd12; // n
                4'd12: gear_idx = 4'd13; // d
                default: gear_idx = 4'hF;
            endcase
            // 동일한 디코더 함수 사용 -> 모양 통일
            seg_1_data = encode_digit(gear_idx);
        end
    end

endmodule