module Display_Unit (
    input clk, 
    input rst,              // �� ���� �߰� (�ʱ�ȭ��)
    input tick_scan, 
    input obd_mode_sw,
    input [13:0] rpm, 
    input [7:0] speed, 
    input [7:0] fuel, 
    input [7:0] temp, 
    input [3:0] gear_char, 
    
    // 8-Digit 7-Segment
    output reg [7:0] seg_data = 0, 
    output reg [7:0] seg_com = 0,

    // 1-Digit 7-Segment
    output reg [7:0] seg_1_data = 0
);

    reg [15:0] left_val = 0, right_val = 0; 
    reg [2:0] scan_idx = 0; 
    reg [3:0] hex_digit = 0;

    // --- 1. ������ ���� ---
    always @(*) begin
        if (obd_mode_sw) begin 
            left_val = {8'b0, fuel}; right_val = {8'b0, temp}; 
        end else begin 
            left_val = {2'b0, rpm}; right_val = {8'b0, speed}; 
        end
    end

    // --- 2. ��ĵ Ÿ�̹� (���� �� 0������) ---
    always @(posedge clk or posedge rst) begin
        if (rst) scan_idx <= 0;
        else if (tick_scan) scan_idx <= scan_idx + 1;
    end

    // --- 3. 8-Digit ���ڵ� (�� Active High: 1�� ����) ---
    always @(*) begin
        if (rst) begin
            seg_com = 8'hFF; // ���� �� COM �� (Active Low�� 1�� ��)
            seg_data = 8'h00; // ���� �� ������ �� (Active High�� 0�� ��)
        end else begin
            // COM ���� (���� COM�� Active Low�� ǥ��: 0�� �� ���õ�)
            seg_com = 8'hFF; 
            seg_com[scan_idx] = 0; 

            // �ڸ��� ������ ����
            case (scan_idx)
                0: hex_digit = right_val[3:0]; 1: hex_digit = right_val[7:4];
                2: hex_digit = right_val[11:8]; 3: hex_digit = right_val[15:12];
                4: hex_digit = left_val[3:0]; 5: hex_digit = left_val[7:4];
                6: hex_digit = left_val[11:8]; 7: hex_digit = left_val[15:12];
            endcase
            
            // �� ������ ���� (Active High: 1�� �� ����)
            // ����: dp, g, f, e, d, c, b, a
            case (hex_digit)
                4'h0: seg_data = 8'b0011_1111; // 0 (g, dp ����)
                4'h1: seg_data = 8'b0000_0110; // 1 (b,c ����)
                4'h2: seg_data = 8'b0101_1011; // 2
                4'h3: seg_data = 8'b0100_1111; // 3
                4'h4: seg_data = 8'b0110_0110; // 4
                4'h5: seg_data = 8'b0110_1101; // 5
                4'h6: seg_data = 8'b0111_1101; // 6
                4'h7: seg_data = 8'b0000_0111; // 7 (a,b,c ����)
                4'h8: seg_data = 8'b0111_1111; // 8
                4'h9: seg_data = 8'b0110_1111; // 9
                4'hA: seg_data = 8'b0111_0111; // A
                4'hB: seg_data = 8'b0111_1100; // b
                4'hC: seg_data = 8'b0011_1001; // C
                4'hD: seg_data = 8'b0101_1110; // d
                4'hE: seg_data = 8'b0111_1001; // E
                4'hF: seg_data = 8'b0111_0001; // F
                default: seg_data = 8'b0000_0000; // OFF
            endcase
        end
    end

    // --- 4. 1-Digit ��� ǥ�� (�� Active High: 1�� ����) ---
    always @(*) begin
        if (rst) seg_1_data = 8'h00; // ���� �� ��
        else begin
            case (gear_char)
                // P: a,b,e,f,g ON -> 0111_0011 (Active High)
                // 8'b dp(0) g(1) f(1) e(1) d(0) c(0) b(1) a(1)
                4'd3: seg_1_data = 8'b0111_0011; 
                
                // R (r): e, g ON
                // 8'b 0101_0000
                4'd6: seg_1_data = 8'b0101_0000; 
                
                // N (n): c, e, g ON
                // 8'b 0101_0100
                4'd9: seg_1_data = 8'b0101_0100; 
                
                // D (d): b, c, d, e, g ON
                // 8'b 0101_1110
                4'd12: seg_1_data = 8'b0101_1110; 
                
                // �� ��: ��� ��
                default: seg_1_data = 8'b0000_0000; 
            endcase
        end
    end

endmodule