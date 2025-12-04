module Car_Simulator_Top (
    input CLK,
    // 키패드
    input KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6,
    input KEY_7, KEY_8, KEY_9, KEY_STAR, KEY_0, KEY_SHARP,
    // 스위치 & ADC
    input [7:0] DIP_SW,
    output SPI_SCK, SPI_AD, SPI_DIN, input SPI_DOUT,
    // 출력
    output [7:0] SEG_DATA, SEG_COM,
    output PIEZO,
    output [7:0] LED,
    output LCD_RS, LCD_RW, LCD_E, output [7:0] LCD_DATA,
    output [7:0] SEG_1_DATA, 
    
    output SERVO_PWM,
    output [3:0] FC_RED, output [3:0] FC_GREEN, output [3:0] FC_BLUE,
    output [3:0] STEP_MOTOR
);

    wire tick_1s, tick_spd, tick_scn, tick_snd;
    wire [7:0] spd_w, fuel_w, temp_w, adc_accel_w, adc_cds_w;
    wire [13:0] rpm_w;
    wire [31:0] odo_w;
    wire ess_trig, led_l, led_r;
    wire accel_active;
    
    reg [3:0] gear_reg = 4'd3;
    reg engine_on = 1'b0;

    // 리셋 로직
    wire global_safe_rst;
    assign global_safe_rst = (KEY_8 && (spd_w == 0) && (gear_reg == 4'd3) && KEY_STAR && DIP_SW[7]);

    // --- 클럭 및 ADC ---
    Clock_Gen u_clk (.clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s), .tick_speed(tick_spd), .tick_scan(tick_scn));
    SPI_ADC_Controller u_adc (.clk(CLK), .rst(global_safe_rst), .spi_sck(SPI_SCK), .spi_cs_n(SPI_AD), .spi_mosi(SPI_DIN), .spi_miso(SPI_DOUT), .adc_accel(adc_accel_w), .adc_cds(adc_cds_w));

    assign accel_active = (adc_accel_w > 8'd10);
    
    // Warning Light Logic (ESS Timer)
    wire ess_active_wire;
    Warning_Light_Logic u_warn (
        .clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s),
        .sw_hazard(DIP_SW[2]), .ess_trigger(ess_trig), 
        .is_accel_pressed(accel_active),
        .blink_out(), 
        .ess_active_out(ess_active_wire)
    );

    // --- 시동 FSM ---
    parameter STATE_OFF = 2'd0;
    parameter STATE_ACC = 2'd1;
    parameter STATE_RUN = 2'd2;
    reg [1:0] power_state = STATE_OFF;
    
    reg prev_key_0;
    
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) begin
            power_state <= STATE_OFF;
            prev_key_0 <= 0;
        end else if (tick_spd) begin 
            prev_key_0 <= KEY_0;
            
            // [Feature] Engine Stalls if Fuel is Empty
            if (power_state == STATE_RUN && fuel_w == 0) begin
                power_state <= STATE_ACC; 
            end
            
            if (KEY_0 && !prev_key_0) begin
                case (power_state)
                    STATE_OFF: begin
                        if (KEY_STAR && gear_reg == 4'd3) begin
                            // Only start if fuel > 0
                            if (fuel_w > 0) power_state <= STATE_RUN;
                            else power_state <= STATE_ACC;
                        end
                        else power_state <= STATE_ACC; 
                    end
                    STATE_ACC: begin
                        if (KEY_STAR && gear_reg == 4'd3) begin
                            // Only start if fuel > 0
                            if (fuel_w > 0) power_state <= STATE_RUN;
                        end
                        else power_state <= STATE_OFF; 
                    end
                    STATE_RUN: begin
                        if (spd_w == 0) power_state <= STATE_OFF;
                    end
                endcase
            end
        end
    end

    always @(*) engine_on = (power_state == STATE_RUN);

    // --- 기어 변경 ---
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) gear_reg <= 4'd3;
        else begin
            if (KEY_3) gear_reg <= 4'd3;      // P
            else if (KEY_6) begin             // R (Reverse)
                // [Safety] Only allow shifting to Reverse when speed is 0
                if (spd_w == 0) gear_reg <= 4'd6; 
            end
            else if (KEY_9) gear_reg <= 4'd9; // N
            else if (KEY_SHARP) gear_reg <= 4'd12; // D
        end
    end

    Vehicle_Logic u_logic (.clk(CLK), .rst(global_safe_rst), .engine_on(engine_on), .tick_1sec(tick_1s), .tick_speed(tick_spd), .current_gear(gear_reg), .adc_accel(adc_accel_w), .is_brake_normal(KEY_STAR), .is_brake_hard(KEY_7), .speed(spd_w), .rpm(rpm_w), .fuel(fuel_w), .temp(temp_w), .odometer_raw(odo_w), .ess_trigger(ess_trig));
    
    // --- LED & LCD 제어 ---
    wire [7:0] led_logic_out;
    wire [7:0] lcd_data_logic;
    wire lcd_rs_logic, lcd_rw_logic, lcd_e_logic;
    
    // 브레이크 감지
    wire is_brake_active;
    assign is_brake_active = (KEY_7 || KEY_STAR);

    // [추가] 풀컬러 LED 제어를 위한 중간 와이어
    wire [3:0] fc_r_w, fc_g_w, fc_b_w;

    Turn_Signal_Logic u_sig (.clk(CLK), .rst(global_safe_rst), .sw_left(DIP_SW[0]), .sw_right(DIP_SW[1]), .sw_hazard(DIP_SW[2]), .ess_active(ess_active_wire), .led_left(led_l), .led_right(led_r));
    
    // [수정] Light_Controller는 입력 조건을 따지지 않고 그냥 연결합니다.
    // 대신 출력(FC_RED 등)을 와이어(fc_r_w)에 받아서 아래에서 제어합니다.
    Light_Controller u_light (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .sw_headlight(DIP_SW[3]), 
        .sw_high_beam(DIP_SW[4]), 
        .cds_val(adc_cds_w), 
        .is_brake(is_brake_active), 
        .is_reverse(gear_reg == 4'd6), 
        .turn_left(led_l), 
        .turn_right(led_r), 
        .fc_red(fc_r_w),   // [변경] 중간 와이어로 연결
        .fc_green(fc_g_w), // [변경]
        .fc_blue(fc_b_w),  // [변경]
        .led_port(led_logic_out)
    );

    // [수정된 LED 로직] 
    assign LED = (engine_on) ? led_logic_out : 
                 ((DIP_SW[2] ? (led_logic_out & 8'b11000011) : 8'b0) | 
                  (is_brake_active ? 8'b00111100 : 8'b0));

    // [추가된 풀컬러 LED 로직]
    // 시동이 켜졌을 때만(engine_on) 와이어 값을 내보내고, 아니면 0(꺼짐)을 내보냅니다.
    assign FC_RED   = (engine_on) ? fc_r_w : 4'd0;
    assign FC_GREEN = (engine_on) ? fc_g_w : 4'd0;
    assign FC_BLUE  = (engine_on) ? fc_b_w : 4'd0;

    Step_Motor_Controller u_steer (
        .clk(CLK),
        .rst(global_safe_rst),
        .engine_on(engine_on || (power_state == STATE_ACC)), 
        .key_left(KEY_4),    
        .key_right(KEY_5),   
        .key_center(KEY_2),  
        .step_out(STEP_MOTOR)
    );

    // 7-Segment (TPS 표시 기능 추가됨)
    Display_Unit u_disp (
        .clk(CLK), 
        .rst(global_safe_rst || (power_state == STATE_OFF)), 
        .tick_scan(tick_scn), .obd_mode_sw(DIP_SW[7]), 
        .rpm(engine_on ? rpm_w : 14'd0), 
        .speed(engine_on ? spd_w : 8'd0), 
        .fuel(engine_on ? fuel_w : 8'd0), 
        .temp(engine_on ? temp_w : 8'd0), 
        .gear_char(gear_reg), 
        .seg_data(SEG_DATA), .seg_com(SEG_COM), .seg_1_data(SEG_1_DATA)
    );

    // LCD (시동 OFF 시 꺼짐 신호 전달)
    LCD_Module u_lcd (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .engine_on(engine_on), 
        .is_off(power_state == STATE_OFF), 
        .odometer(odo_w), 
        .fuel(fuel_w), 
        .is_side_brake(DIP_SW[6]), 
        .lcd_rs(lcd_rs_logic), .lcd_rw(lcd_rw_logic), .lcd_e(lcd_e_logic), .lcd_data(lcd_data_logic)
    );
    
    // LCD 신호 차단 (제거됨 - 항상 신호 전달)
    assign LCD_RS   = lcd_rs_logic; 
    assign LCD_RW   = lcd_rw_logic;
    assign LCD_E    = lcd_e_logic;
    assign LCD_DATA = lcd_data_logic;

    Servo_Controller u_servo (.clk(CLK), .rst(global_safe_rst), .speed(spd_w), .servo_pwm(SERVO_PWM));
    Sound_Unit u_snd (.clk(CLK), .rst(global_safe_rst), .rpm(rpm_w), .ess_active(led_l | led_r), .is_horn(KEY_1), .is_reverse(gear_reg == 4'd6), .turn_signal_on(led_l | led_r), .engine_on(engine_on), .accel_active(accel_active), .piezo_out(PIEZO));

endmodule
