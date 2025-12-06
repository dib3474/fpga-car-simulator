module Step_Motor_Controller (
    input clk,              // 50MHz
    input rst,
    input engine_on,        // �õ� ����
    input key_left,         // 4�� Ű (��ȸ��)
    input key_right,        // 5�� Ű (��ȸ��)
    input key_center,       // 2�� Ű (����ġ ����)
    output reg [3:0] step_out // ���� ���
);

    // --- 1. �ӵ� �� �Ÿ� ���� ---
    
    // [�Ŀ� �ڵ� ON] �õ� ������ �� �ӵ� (���� �ӵ�)
    parameter SPEED_FAST = 900_000; 
    
    // [�Ŀ� �ڵ� OFF] �õ� ������ �� �ӵ� (4�� ������ -> ���ſ� ����)
    parameter SPEED_SLOW = 1_600_000; 

    // �� ���� �� ���� (����� ������ ����)
    parameter LIMIT_POS = 75; 

    reg [21:0] cnt; // ī���� ��Ʈ�� �˳��ϰ� ���� (20->21)
    reg tick;
    reg [2:0] step_idx; 
    reg signed [31:0] current_pos; 

    // ���� ���¿� ���� �ӵ� ���� (Mux)
    wire [21:0] current_speed_limit;
    assign current_speed_limit = (engine_on) ? SPEED_FAST : SPEED_SLOW;

    // --- 2. �ӵ�(Tick) ���� ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt <= 0; tick <= 0;
        end else begin
            // engine_on ���ο� ���� ��ǥ ī��Ʈ(current_speed_limit)�� �޶���
            if (cnt >= current_speed_limit) begin
                cnt <= 0; tick <= 1;
            end else begin
                cnt <= cnt + 1; tick <= 0;
            end
        end
    end

    // --- 3. ���� ���� ���� ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            step_idx <= 0;
            step_out <= 4'b0000;
            current_pos <= 0; 
        end else if (tick) begin 
            // [������] && engine_on ���� ����! 
            // ���� �õ��� ������ tick(���� �ӵ�)�� �߻��ϸ� �����Դϴ�.

            // (1) 좌회전 (4번 키) -> 반대로 동작하도록 수정 (감소)
            if (key_left && !key_right) begin
                if (current_pos > -LIMIT_POS) begin
                    step_idx <= step_idx - 1;
                    current_pos <= current_pos - 1;
                end
            end 
            
            // (2) 우회전 (5번 키) -> 반대로 동작하도록 수정 (증가)
            else if (key_right && !key_left) begin
                if (current_pos < LIMIT_POS) begin
                    step_idx <= step_idx + 1;
                    current_pos <= current_pos + 1;
                end
            end
            
            // (3) ����ġ ���� (2�� Ű)
            else if (key_center) begin
                if (current_pos > 0) begin       
                    step_idx <= step_idx - 1;    
                    current_pos <= current_pos - 1;
                end else if (current_pos < 0) begin 
                    step_idx <= step_idx + 1;   
                    current_pos <= current_pos + 1;
                end
            end
            
            // ���� ���
            case (step_idx)
                3'd0: step_out <= 4'b1000;
                3'd1: step_out <= 4'b1100;
                3'd2: step_out <= 4'b0100;
                3'd3: step_out <= 4'b0110;
                3'd4: step_out <= 4'b0010;
                3'd5: step_out <= 4'b0011;
                3'd6: step_out <= 4'b0001;
                3'd7: step_out <= 4'b1001;
            endcase
        end 
        // [������] else if (!engine_on) ����. 
        // �õ� ������ ���Ϳ� ������ ���� �ڵ��� ���� �� ���� (��ũ ���� or ȸ��)
    end

endmodule