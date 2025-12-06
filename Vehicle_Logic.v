module Vehicle_Logic (
    input clk, input rst,
    input engine_on,
    input tick_1sec, input tick_speed,
    input [3:0] current_gear, 
    input [7:0] adc_accel,
    input is_brake_normal, input is_brake_hard,
    
    // [입력]
    input is_side_brake,    
    input is_low_mode,      // DIP 6번
    input btn_gear_up,      // Top에서 KEY_6 연결됨
    input btn_gear_down,    // Top에서 KEY_SHARP 연결됨

    output reg [7:0] speed = 0,
    output reg [13:0] rpm = 0,
    output reg [7:0] fuel = 100,
    output reg [7:0] temp = 25,
    output reg [31:0] odometer_raw = 0,
    output reg ess_trigger = 0,
    output reg [2:0] gear_num = 1
);
    parameter IDLE_RPM = 800;
    
    reg [9:0] power;      
    reg [10:0] resistance; 
    
    wire [7:0] effective_accel;
    assign effective_accel = (adc_accel > 5) ? (adc_accel - 5) : 8'd0;

    // --- Low Mode Limit Control ---
    reg [2:0] max_gear_limit; 
    reg prev_up, prev_down;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            max_gear_limit <= 3; 
            prev_up <= 0; prev_down <= 0;
        end else begin
            if (is_low_mode) begin
                if (btn_gear_up && !prev_up && max_gear_limit < 3)
                    max_gear_limit <= max_gear_limit + 1;
                else if (btn_gear_down && !prev_down && max_gear_limit > 1)
                    max_gear_limit <= max_gear_limit - 1;
            end else begin
                max_gear_limit <= 3; 
            end
            prev_up <= btn_gear_up;
            prev_down <= btn_gear_down;
        end
    end

    // --- Physics ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin speed <= 0; ess_trigger <= 0; end
        else if (!engine_on) begin speed <= 0; ess_trigger <= 0; end
        else if (tick_speed) begin
            if (current_gear == 4'd12) power = effective_accel;       
            else if (current_gear == 4'd6) power = effective_accel / 2; 
            else power = 0; 

            resistance = speed + 5 + ((speed >= 180) ? 100 : 0);
            if (is_side_brake) resistance = resistance + 300; 

            if (is_brake_hard) begin 
                if (speed > 150) begin if(speed>=2) speed<=speed-2; else speed<=0; end
                else if (speed > 80) begin if(speed>=4) speed<=speed-4; else speed<=0; end
                else begin if(speed>=8) speed<=speed-8; else speed<=0; end
                if(speed > 50) ess_trigger <= 1; else ess_trigger <= 0;
            end 
            else if (is_brake_normal) begin 
                if (speed > 150) begin if(speed>=1) speed<=speed-1; else speed<=0; end
                else if (speed > 80) begin if(speed>=2) speed<=speed-2; else speed<=0; end
                else begin if(speed>=3) speed<=speed-3; else speed<=0; end
                ess_trigger <= 0;
            end 
            else begin 
                ess_trigger <= 0;
                if (power > resistance) begin
                    if (current_gear == 4'd6 && speed >= 50) begin end 
                    else if (speed < 250) speed <= speed + 1;
                end 
                else if (power < resistance) begin
                    if (speed > 0) speed <= speed - 1;
                end
            end
        end
    end

    // --- RPM & Gear ---
    reg [2:0] auto_gear, final_gear;
    reg [13:0] base_rpm;

    always @(*) begin
        if (!engine_on) begin rpm = 0; gear_num = 1; end
        else if (current_gear == 4'd3 || current_gear == 4'd9) begin 
            reg [13:0] idle_calc;
            idle_calc = IDLE_RPM + (effective_accel * 20);
            if (idle_calc > 4000) rpm = 4000; else rpm = idle_calc;
            gear_num = 1;
        end
        else begin 
            if (speed < 30)       auto_gear = 1;
            else if (speed < 60)  auto_gear = 2;
            else if (speed < 90)  auto_gear = 3;
            else if (speed < 120) auto_gear = 4;
            else if (speed < 150) auto_gear = 5;
            else                  auto_gear = 6;

            if (is_low_mode && (auto_gear > max_gear_limit)) final_gear = max_gear_limit;
            else final_gear = auto_gear;

            gear_num = final_gear; 

            case (final_gear)
                1: base_rpm = speed * 130;
                2: base_rpm = speed * 90;
                3: base_rpm = speed * 65;
                4: base_rpm = speed * 50;
                5: base_rpm = speed * 40;
                6: base_rpm = speed * 30;
                default: base_rpm = speed * 30;
            endcase
            rpm = IDLE_RPM + base_rpm + (effective_accel * 5);
            if (rpm > 8000) rpm = 8000;
        end
    end

    // --- OBD Data ---
    reg [2:0] temp_timer;     
    reg [15:0] dist_cm_acc;   
    reg [15:0] fuel_accum; 
    parameter FUEL_THRESHOLD = 5000; 

    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            fuel <= 100; temp <= 25; odometer_raw <= 0; 
            temp_timer <= 0; dist_cm_acc <= 0; fuel_accum <= 0;
        end
        else if (tick_1sec) begin
            if (engine_on && speed > 0) begin
                dist_cm_acc <= dist_cm_acc + (speed * 28); 
                if (dist_cm_acc >= 100) begin
                    odometer_raw <= odometer_raw + (dist_cm_acc / 100); 
                    dist_cm_acc <= dist_cm_acc % 100;
                end
            end
            if (engine_on) begin
                if (temp_timer >= 1) begin 
                    temp_timer <= 0;
                    if (rpm > 5000 && temp < 130) temp <= temp + 1;
                    else if (temp < 90) begin
                        if (rpm > 2000) temp <= temp + 2; else temp <= temp + 1;
                    end
                    else if (temp >= 90) begin if (temp > 95) temp <= temp - 1; end
                end else temp_timer <= temp_timer + 1;
            end else begin
                if (temp_timer >= 2) begin 
                    temp_timer <= 0; if (temp > 25) temp <= temp - 1;
                end else temp_timer <= temp_timer + 1;
            end
        end
        else if (tick_speed && engine_on) begin
            reg [15:0] drain_amount;
            drain_amount = 2; 
            drain_amount = drain_amount + (rpm / 1000); 
            if (effective_accel > 10) drain_amount = drain_amount + (effective_accel / 5); 
            if (rpm > 1500 && effective_accel == 0) drain_amount = 0; 

            fuel_accum <= fuel_accum + drain_amount;
            if (fuel_accum >= FUEL_THRESHOLD) begin
                if (fuel > 0) fuel <= fuel - 1;
                fuel_accum <= 0; 
            end
        end
    end
endmodule