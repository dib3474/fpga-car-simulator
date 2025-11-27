module Warning_Light_Logic (
    input clk,
    input rst,
    input tick_1sec,         // �ð� ī��Ʈ��
    
    input sw_hazard,         // DIP ����ġ �Է� (SW3)
    input ess_trigger,       // Vehicle_Logic���� �� ������ ��ȣ
    input is_accel_pressed,  // �Ǽ��� ��Ҵ��� ���� (����� ����)
    
    output reg blink_out,     // ���� ���� ������ ��ȣ
    output wire ess_active_out // ESS Active Output
);

    // --- 1. ESS ���� Ÿ�̸� ���� ---
    reg [2:0] ess_timer;     // 3�� ī����
    reg ess_active;          // ESS Ȱ��ȭ ���� �÷���

    assign ess_active_out = ess_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ess_active <= 0;
            ess_timer <= 0;
        end else begin
            // [���� A] ������ ��ȣ�� ������ ESS ��� ����
            if (ess_trigger) begin
                ess_active <= 1;
                ess_timer <= 3; // 3�� ���� ����
            end
            
            // [���� B] ESS ���� ����
            else if (ess_active) begin
                // 1. �Ǽ��� ������ ��� �� (�����)
                if (is_accel_pressed) begin
                    ess_active <= 0;
                    ess_timer <= 0;
                end
                // 2. Ÿ�̸Ӱ� 0�� �Ǹ� ��
                else if (ess_timer == 0) begin
                    ess_active <= 0;
                end
                // 3. Ÿ�̸� ���� (1�ʸ���)
                else if (tick_1sec) begin
                    ess_timer <= ess_timer - 1;
                end
            end
        end
    end

    // --- 2. ������ �ֱ� ���� (0.5�� ����) ---
    reg [24:0] blink_cnt;
    wire blink_pulse;
    // 50MHz Ŭ�� ���� �� 0.5�� (25,000,000)
    always @(posedge clk or posedge rst) begin
        if (rst) blink_cnt <= 0;
        else if (blink_cnt >= 25_000_000) blink_cnt <= 0;
        else blink_cnt <= blink_cnt + 1;
    end
    assign blink_pulse = (blink_cnt < 12_500_000); // 0.5�� ON, 0.5�� OFF

    // --- 3. ���� ��� ���� (OR ����) ---
    always @(*) begin
        // DIP ����ġ(SW3)�� ���� �ְų�(OR) ESS�� Ȱ��ȭ ���¸� ������
        if (sw_hazard || ess_active) begin
            blink_out = blink_pulse;
        end else begin
            blink_out = 0; // �� �� �ƴϸ� ����
        end
    end

endmodule