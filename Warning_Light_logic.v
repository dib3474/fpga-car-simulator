module Warning_Light_Logic (
    input clk,
    input rst,
    input tick_1sec,         // 1sec tick
    
    input sw_hazard,         // DIP Switch Input (SW3)
    input ess_trigger,       // ESS Trigger Signal from Vehicle_Logic
    input is_accel_pressed,  // Accelerator Pressed (Cancel ESS)
    
    output reg blink_out,     // Blink Signal Output
    output wire ess_active_out // ESS Active Output
);

    // --- 1. ESS Timer Logic ---
    reg [2:0] ess_timer;     // 3sec Counter
    reg ess_active;          // ESS Active Flag

    assign ess_active_out = ess_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ess_active <= 0;
            ess_timer <= 0;
        end else begin
            // [Condition A] Trigger ESS on signal
            if (ess_trigger) begin
                ess_active <= 1;
                ess_timer <= 3; // Set 3 seconds
            end
            
            // [Condition B] Maintain ESS
            else if (ess_active) begin
                // 1. Cancel if accelerator is pressed
                if (is_accel_pressed) begin
                    ess_active <= 0;
                    ess_timer <= 0;
                end
                // 2. Cancel if timer expires
                else if (ess_timer == 0) begin
                    ess_active <= 0;
                end
                // 3. Decrement timer (1 sec tick)
                else if (tick_1sec) begin
                    ess_timer <= ess_timer - 1;
                end
            end
        end
    end

    // --- 2. Blink Period Generation (1.0s Period) ---
    reg [25:0] blink_cnt;
    wire blink_pulse;
    // 50MHz Clock -> 1.0s (50,000,000)
    always @(posedge clk or posedge rst) begin
        if (rst) blink_cnt <= 0;
        else if (blink_cnt >= 50_000_000) blink_cnt <= 0;
        else blink_cnt <= blink_cnt + 1;
    end
    assign blink_pulse = (blink_cnt < 25_000_000); // 0.5s ON, 0.5s OFF

    // --- 3. Blink Output Logic (OR Logic) ---
    always @(*) begin
        // Blink if Hazard Switch (SW3) is ON OR ESS is Active
        if (sw_hazard || ess_active) begin
            blink_out = blink_pulse;
        end else begin
            blink_out = 0;
        end
    end

endmodule