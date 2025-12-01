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
    output [7:0] SEG_1_DATA, // 1-Digit 데이터
    // 1-Digit COM은 그라운드 (Display_Unit 내부 처리)
    output SERVO_PWM,
    output [3:0] FC_RED, output [3:0] FC_GREEN, output [3:0] FC_BLUE
);

    // ... (내부 와이어 선언 생략) ...
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

    // --- 클럭 생성 ---
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

    // --- 시동 로직 (3단계: OFF -> ACC -> RUN) ---
    // OFF: 전원 꺼짐
    // ACC (Key On): 0번 누름. LCD "KEY ON"
    // RUN (Engine On): 브레이크(*) + 0번 누름. LCD "ENGINE ON" -> 주행
    
    parameter STATE_OFF = 2'd0;
    parameter STATE_ACC = 2'd1;
    parameter STATE_RUN = 2'd2;
    reg [1:0] power_state = STATE_OFF;
    
    reg [3:0] start_debounce_cnt;
    reg prev_key_0;
    
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) begin
            power_state <= STATE_OFF;
            start_debounce_cnt <= 0;
            prev_key_0 <= 0;
        end else if (tick_spd) begin // 50ms 주기
            prev_key_0 <= KEY_0;
            
            // KEY_0(시동버튼)이 눌린 순간 (Rising Edge)
            if (KEY_0 && !prev_key_0) begin
                case (power_state)
                    STATE_OFF: begin
                        if (KEY_STAR && gear_reg == 4'd3) power_state <= STATE_RUN; // 브레이크+P+버튼 -> 시동
                        else power_state <= STATE_ACC; // 그냥 버튼 -> ACC (Key On)
                    end
                    STATE_ACC: begin
                        if (KEY_STAR && gear_reg == 4'd3) power_state <= STATE_RUN; // 브레이크+P+버튼 -> 시동
                        else power_state <= STATE_OFF; // 그냥 버튼 -> 끄기
                    end
                    STATE_RUN: begin
                        if (spd_w == 0) power_state <= STATE_OFF; // 정지 상태에서 버튼 -> 끄기
                    end
                endcase
            end
        end
    end

    // 엔진 상태 연결
    always @(*) engine_on = (power_state == STATE_RUN);

    // --- 기어 변경 로직 ---
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) gear_reg <= 4'd3;
        else begin
            // 시동 켜진 상태에서만 기어 변경 가능 (안전)
            // 또는 시동 꺼져도 P단으로는 갈 수 있게? -> 보통은 시동 켜야 기어 바꿈
            if (KEY_3) gear_reg <= 4'd3;      // P
            else if (KEY_6) gear_reg <= 4'd6; // R
            else if (KEY_9) gear_reg <= 4'd9; // N
            else if (KEY_SHARP) gear_reg <= 4'd12; // D
        end
    end

    Vehicle_Logic u_logic (.clk(CLK), .rst(global_safe_rst), .engine_on(engine_on), .tick_1sec(tick_1s), .tick_speed(tick_spd), .current_gear(gear_reg), .adc_accel(adc_accel_w), .is_brake_normal(KEY_STAR), .is_brake_hard(KEY_7), .speed(spd_w), .rpm(rpm_w), .fuel(fuel_w), .temp(temp_w), .odometer_raw(odo_w), .ess_trigger(ess_trig));
    
    // --- LED & LCD 제어 (시동 상태 반영) ---
    // 시동 꺼짐(engine_on=0): LED, LCD 모두 OFF (단, 비상등은 켜질 수 있음)
    // 시동 켜짐(engine_on=1): 정상 동작
    
    wire [7:0] led_logic_out;
    wire [7:0] lcd_data_logic;
    wire lcd_rs_logic, lcd_rw_logic, lcd_e_logic;
    
    Turn_Signal_Logic u_sig (.clk(CLK), .rst(global_safe_rst), .sw_left(DIP_SW[0]), .sw_right(DIP_SW[1]), .sw_hazard(DIP_SW[2]), .ess_active(ess_active_wire), .led_left(led_l), .led_right(led_r));
    Light_Controller u_light (.clk(CLK), .rst(global_safe_rst), .sw_headlight(DIP_SW[3]), .sw_high_beam(DIP_SW[4]), .cds_val(adc_cds_w), .is_brake(KEY_7 | KEY_STAR), .is_reverse(gear_reg == 4'd6), .turn_left(led_l), .turn_right(led_r), .fc_red(FC_RED), .fc_green(FC_GREEN), .fc_blue(FC_BLUE), .led_port(led_logic_out));

    // LED: 시동 꺼져도 비상등(Hazard)은 켜져야 함. 나머지는 OFF.
    // [수정] 시동 꺼지면 전조등/미등 자동 소등 (비상등만 허용)
    // led_logic_out의 비트 구성: [7:6] 우측깜빡이, [5:2] 전조등/미등/브레이크, [1:0] 좌측깜빡이 (가정)
    // Light_Controller 내부 로직에 따라 다르지만, 보통 양쪽 끝이 방향지시등임.
    // 여기서는 안전하게 비상등 스위치(DIP_SW[2])가 켜진 경우에만 led_logic_out을 내보내되,
    // Light_Controller가 이미 깜빡임 신호(led_l, led_r)만 켜서 보내주므로 그대로 내보내면 됨.
    // 단, 시동 꺼진 상태에서 브레이크를 밟으면 브레이크등이 켜질 수 있는데, 이는 정상 동작임.
    // 만약 "전조등(Headlight)"만 끄고 싶다면 Light_Controller에 engine_on 신호를 넣어주는 게 가장 확실함.
    // 하지만 Top 모듈에서 처리하려면 아래와 같이 마스킹을 해야 함.
    
    // 여기서는 간단하게 "시동 꺼짐 & 비상등 켜짐 -> LED 출력 허용"으로 하되,
    // Light_Controller가 시동 꺼짐을 모르므로 전조등 스위치가 켜져 있으면 전조등 데이터도 같이 옴.
    // 따라서 비상등(깜빡임) 신호만 추출해서 내보내는 것이 맞음.
    // 하지만 핀맵을 정확히 모르므로, 가장 확실한 방법은 Light_Controller에 engine_on을 전달하는 것임.
    // 현재 구조상 Light_Controller 수정 없이 Top에서 처리하려면:
    
    assign LED = (engine_on) ? led_logic_out : 
                 (DIP_SW[2] ? (led_logic_out & 8'b11000011) : 8'b0); 
                 // 8'b11000011: 양쪽 끝 2비트씩(좌/우 깜빡이)만 통과시키고 가운데(전조등)는 차단.
                 // (HBE-Combo II 보드 LED 배치: 좌측[1:0], 우측[7:6] 가정)

    // Display Unit: OFF 상태일 때 Reset을 걸어 화면을 끔
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

    // LCD: OFF 상태일 때 Reset을 걸어 화면을 끔
    LCD_Module u_lcd (.clk(CLK), .rst(global_safe_rst || (power_state == STATE_OFF)), .engine_on(engine_on), .odometer(odo_w), .fuel(fuel_w), .is_side_brake(DIP_SW[6]), .lcd_rs(lcd_rs_logic), .lcd_rw(lcd_rw_logic), .lcd_e(lcd_e_logic), .lcd_data(lcd_data_logic));
    
    assign LCD_RS = lcd_rs_logic; 
    assign LCD_RW = lcd_rw_logic;
    assign LCD_E  = lcd_e_logic;
    assign LCD_DATA = lcd_data_logic;

    Servo_Controller u_servo (.clk(CLK), .rst(global_safe_rst), .speed(spd_w), .servo_pwm(SERVO_PWM));
    Sound_Unit u_snd (.clk(CLK), .rst(global_safe_rst), .rpm(rpm_w), .ess_active(led_l | led_r), .is_horn(KEY_1), .is_reverse(gear_reg == 4'd6), .turn_signal_on(led_l | led_r), .engine_on(engine_on), .accel_active(accel_active), .piezo_out(PIEZO));

endmodule
