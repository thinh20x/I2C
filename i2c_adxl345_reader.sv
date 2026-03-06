`timescale 1ns / 1ps

module i2c_adxl345_reader #(
    parameter SYS_CLK_FREQ = 12_000_000, // 12 MHz
    parameter I2C_FREQ     = 100_000     // 100 kHz (Standard Mode)
)(
    input  logic       clk,
    input  logic       rst_n,
    
    // External Control & Data Interface
    input  logic       start_read_req, // Xung kích hoạt bắt đầu chuỗi đọc (pulse)
    output logic [7:0] adxl_data_out,  // Dữ liệu đọc về từ ADXL345
    output logic       adxl_data_valid,// Báo hiệu dữ liệu đọc về hợp lệ (pulse)
    output logic       read_done,      // Báo hiệu đã chạy xong toàn bộ chuỗi lệnh (pulse)
    output logic       busy,           // Module đang bận chạy chuỗi lệnh
    
    // I2C Physical Interface
    inout  wire        sda,
    inout  wire        scl
);

    // =====================================================================
    // 1. COMMAND ROM (SEQUENCER)
    // =====================================================================
    localparam PROG_LENGTH = 4;
    logic [11:0] cmd_rom [0:PROG_LENGTH-1];

    // Khởi tạo ROM lệnh (Đọc thanh ghi 0x32 của ADXL345, Device Addr = 0x53)
    // Cấu trúc: {STOP[11], START[10], READ[9], ACK_EXP[8], DATA[7:0]}
    initial begin
        cmd_rom[0] = {1'b0, 1'b1, 1'b0, 1'b0, 8'hA6}; // START + WRITE Addr 0xA6
        cmd_rom[1] = {1'b0, 1'b0, 1'b0, 1'b0, 8'h32}; // WRITE Reg Addr 0x32
        cmd_rom[2] = {1'b0, 1'b1, 1'b0, 1'b0, 8'hA7}; // REP_START + WRITE Addr 0xA7 (Read Mode)
        cmd_rom[3] = {1'b1, 1'b0, 1'b1, 1'b1, 8'h00}; // READ 1 byte + NACK + STOP
    end

    logic [2:0]  cmd_index;
    logic [11:0] current_cmd;
    logic        cmd_valid;
    wire         cmd_ready; // Tín hiệu từ FSM báo đã nhận xong lệnh
    
    assign current_cmd = cmd_rom[cmd_index];

    // Sequencer Control Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_index <= 3'd0;
            cmd_valid <= 1'b0;
            busy      <= 1'b0;
            read_done <= 1'b0;
        end else begin
            read_done <= 1'b0; // Default clear pulse
            
            if (!busy) begin
                if (start_read_req) begin
                    busy      <= 1'b1;
                    cmd_index <= 3'd0;
                    cmd_valid <= 1'b1; // Bật cờ valid để đẩy lệnh đầu tiên
                end
            end else begin
                // Đang bận chạy chuỗi lệnh
                if (cmd_ready && cmd_valid) begin
                    // I2C FSM đã nuốt lệnh hiện tại, chuẩn bị chuyển sang lệnh tiếp theo
                    if (cmd_index == PROG_LENGTH - 1) begin
                        // Đã chạy hết chương trình
                        cmd_valid <= 1'b0;
                        busy      <= 1'b0;
                        read_done <= 1'b1;
                    end else begin
                        // Chuyển sang lệnh kế tiếp
                        cmd_index <= cmd_index + 1'b1;
                        cmd_valid <= 1'b1; // Tiếp tục valid lệnh mới
                    end
                end
            end
        end
    end

    // =====================================================================
    // 2. I2C MASTER FSM ENGINE
    // =====================================================================
    localparam TOTAL_CYCLES = SYS_CLK_FREQ / I2C_FREQ; // 120
    localparam PHASE_25     = TOTAL_CYCLES / 4;        // 30 
    localparam PHASE_50     = TOTAL_CYCLES / 2;        // 60 
    localparam PHASE_75     = (TOTAL_CYCLES * 3) / 4;  // 90 

    typedef enum logic [2:0] {
        IDLE      = 3'd0,
        START     = 3'd1,
        TX_BYTE   = 3'd2,
        ACK_CHECK = 3'd3,
        RX_BYTE   = 3'd4,
        ACK_SEND  = 3'd5,
        STOP      = 3'd6
    } state_t;
    state_t state, next_state;

    logic [6:0] sys_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;
    
    logic sda_out, scl_out;
    logic sda_in, scl_in;
    
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;
    assign scl = (scl_out == 1'b0) ? 1'b0 : 1'bz;
    assign sda_in = sda;
    assign scl_in = scl;

    // Output port connections
    logic [7:0] i2c_rx_data;
    logic       i2c_rx_valid;
    
    always_ff @(posedge clk) begin
        if (i2c_rx_valid) begin
            adxl_data_out   <= i2c_rx_data;
            adxl_data_valid <= 1'b1;
        end else begin
            adxl_data_valid <= 1'b0;
        end
    end

    // --- SCL Generator & Clock Stretching ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_cnt <= '0;
        end else if (state != IDLE) begin
            if (sys_cnt == PHASE_50 - 1 && scl_in == 1'b0 && scl_out == 1'b1) begin
                sys_cnt <= sys_cnt; // Clock Stretching
            end else if (sys_cnt == TOTAL_CYCLES - 1) begin
                sys_cnt <= '0;
            end else begin
                sys_cnt <= sys_cnt + 1'b1;
            end
        end else begin
            sys_cnt <= '0;
        end
    end

    // --- FSM State Update ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else if (sys_cnt == TOTAL_CYCLES - 1 || state == IDLE) state <= next_state; 
        // Note: Cập nhật state ngay lập tức nếu đang ở IDLE và có lệnh
    end

    // --- Next State Logic & Control Signals ---
    always_comb begin
        next_state = state;
        cmd_ready  = 1'b0;
        i2c_rx_valid = 1'b0;
        
        case (state)
            IDLE: begin
                if (cmd_valid) begin
                    if (current_cmd[10]) next_state = START;
                    else next_state = current_cmd[9] ? RX_BYTE : TX_BYTE;
                end
            end
            
            START: next_state = current_cmd[9] ? RX_BYTE : TX_BYTE;
            
            TX_BYTE: begin
                if (bit_cnt == 7) next_state = ACK_CHECK;
            end
            
            ACK_CHECK: begin
                if (current_cmd[11]) begin
                    next_state = STOP;
                    cmd_ready  = 1'b1; 
                end else begin
                    cmd_ready  = 1'b1;
                    next_state = IDLE; 
                end
            end
            
            RX_BYTE: begin
                if (bit_cnt == 7) next_state = ACK_SEND;
            end
            
            ACK_SEND: begin
                i2c_rx_valid = 1'b1; 
                if (current_cmd[11]) begin
                    next_state = STOP;
                    cmd_ready  = 1'b1;
                end else begin
                    cmd_ready  = 1'b1;
                    next_state = IDLE;
                end
            end
            
            STOP: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // --- Output Datapath Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_out   <= 1'b1;
            scl_out   <= 1'b1;
            bit_cnt   <= '0;
            shift_reg <= '0;
            i2c_rx_data <= '0;
        end else begin
            case (state)
                IDLE: begin
                    sda_out <= 1'b1;
                    scl_out <= 1'b1;
                    if (cmd_valid) shift_reg <= current_cmd[7:0];
                end
                
                START: begin
                    if (sys_cnt == 0)        scl_out <= 1'b1; // Giữ SCL cao từ IDLE
                    if (sys_cnt == PHASE_25) sda_out <= 1'b0; // SDA rơi tạo START
                    if (sys_cnt == PHASE_75) scl_out <= 1'b0; // SCL rơi, sẵn sàng truyền
                    bit_cnt <= '0;
                end
                
                TX_BYTE: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= shift_reg[7-bit_cnt];
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                    
                    if (sys_cnt == TOTAL_CYCLES - 1) bit_cnt <= bit_cnt + 1'b1;
                end
                
                ACK_CHECK: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b1; // Master nhả SDA
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                end
                
                RX_BYTE: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b1; // Master nhả SDA
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                    if (sys_cnt == PHASE_75) i2c_rx_data[7-bit_cnt] <= sda_in;
                    
                    if (sys_cnt == TOTAL_CYCLES - 1) bit_cnt <= bit_cnt + 1'b1;
                end
                
                ACK_SEND: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= current_cmd[8]; 
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                end
                
                STOP: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b0; 
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1; 
                    if (sys_cnt == PHASE_75) sda_out <= 1'b1; // Tạo STOP
                end
            endcase
        end
    end

endmodule
