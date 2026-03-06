module i2c_master_engine #(
    parameter SYS_CLK_FREQ = 12_000_000,
    parameter I2C_FREQ     = 100_000
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Command FIFO Interface
    input  logic [11:0] cmd_data,  // [11:STOP, 10:START, 9:READ, 8:ACK_CTRL, 7:0:DATA]
    input  logic        cmd_valid,
    output logic        cmd_ready, // Báo cho FIFO pop lệnh tiếp theo
    
    // Receive Data Interface (To RX FIFO)
    output logic [7:0]  rx_data,
    output logic        rx_valid,
    
    // I2C Physical Interface
    inout  wire         sda,
    inout  wire         scl
);

    localparam TOTAL_CYCLES = SYS_CLK_FREQ / I2C_FREQ; // 120
    localparam PHASE_25     = TOTAL_CYCLES / 4;        // 30 (SDA Change)
    localparam PHASE_50     = TOTAL_CYCLES / 2;        // 60 (SCL Rise)
    localparam PHASE_75     = (TOTAL_CYCLES * 3) / 4;  // 90 (SDA Sample)

    // Trạng thái FSM
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

    // Registers
    logic [6:0] sys_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;
    
    // I/O Buffers (Open-Drain)
    logic sda_out, scl_out;
    logic sda_in, scl_in;
    
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;
    assign scl = (scl_out == 1'b0) ? 1'b0 : 1'bz;
    assign sda_in = sda;
    assign scl_in = scl;

    // SCL Generator & Clock Stretching
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_cnt <= '0;
        end else if (state != IDLE) begin
            // Clock Stretching Handling at 50% phase
            if (sys_cnt == PHASE_50 - 1 && scl_in == 1'b0 && scl_out == 1'b1) begin
                sys_cnt <= sys_cnt; // Hold counter, wait for Slave to release SCL
            end else if (sys_cnt == TOTAL_CYCLES - 1) begin
                sys_cnt <= '0;
            end else begin
                sys_cnt <= sys_cnt + 1'b1;
            end
        end else begin
            sys_cnt <= '0;
        end
    end

    // FSM Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else if (sys_cnt == TOTAL_CYCLES - 1) state <= next_state; // Chuyển state ở cuối chu kỳ
    end

    // Next State Logic & Datapath
    always_comb begin
        next_state = state;
        cmd_ready  = 1'b0;
        rx_valid   = 1'b0;
        
        case (state)
            IDLE: begin
                if (cmd_valid) begin
                    if (cmd_data[10]) next_state = START;
                    else next_state = cmd_data[9] ? RX_BYTE : TX_BYTE;
                end
            end
            
            START: next_state = cmd_data[9] ? RX_BYTE : TX_BYTE;
            
            TX_BYTE: begin
                if (bit_cnt == 7) next_state = ACK_CHECK;
            end
            
            ACK_CHECK: begin
                // Bỏ qua check Arbitration tạm thời để dễ hiểu
                if (cmd_data[11]) begin
                    next_state = STOP;
                    cmd_ready  = 1'b1; // Tiêu thụ xong lệnh
                end else begin
                    cmd_ready  = 1'b1;
                    next_state = IDLE; // Quay về IDLE để lấy lệnh mới ngay lập tức
                end
            end
            
            RX_BYTE: begin
                if (bit_cnt == 7) next_state = ACK_SEND;
            end
            
            ACK_SEND: begin
                rx_valid = 1'b1; // Xuất dữ liệu đã đọc
                if (cmd_data[11]) begin
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

    // Output Logic (SCL, SDA) dựa trên pha của sys_cnt
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_out   <= 1'b1;
            scl_out   <= 1'b1;
            bit_cnt   <= '0;
            shift_reg <= '0;
            rx_data   <= '0;
        end else begin
            case (state)
                IDLE: begin
                    sda_out <= 1'b1;
                    scl_out <= 1'b1;
                    if (cmd_valid) shift_reg <= cmd_data[7:0]; // Load data
                end
                
                START: begin
                    scl_out <= 1'b1;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b0; // SDA falls while SCL is high
                    if (sys_cnt == PHASE_75) scl_out <= 1'b0; // Chuẩn bị cho phase tiếp theo
                    bit_cnt <= '0;
                end
                
                TX_BYTE: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= shift_reg[7-bit_cnt]; // Update SDA
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;                 // SCL Rise
                    
                    if (sys_cnt == TOTAL_CYCLES - 1) bit_cnt <= bit_cnt + 1'b1;
                end
                
                ACK_CHECK: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b1; // Thả SDA cho Slave báo ACK
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                    if (sys_cnt == PHASE_75) begin
                        // Đọc sda_in tại đây. Nếu sda_in == 0 là ACK tốt. 
                        // Có thể lưu cờ error nếu sda_in == 1 (NACK).
                    end
                end
                
                RX_BYTE: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b1; // Master thả đường truyền
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                    if (sys_cnt == PHASE_75) rx_data[7-bit_cnt] <= sda_in; // Sample SDA
                    
                    if (sys_cnt == TOTAL_CYCLES - 1) bit_cnt <= bit_cnt + 1'b1;
                end
                
                ACK_SEND: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= cmd_data[8]; // Gửi ACK(0) hoặc NACK(1) dựa vào bit 8
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1;
                end
                
                STOP: begin
                    if (sys_cnt == 0)        scl_out <= 1'b0;
                    if (sys_cnt == PHASE_25) sda_out <= 1'b0; // Đảm bảo SDA thấp
                    if (sys_cnt == PHASE_50) scl_out <= 1'b1; // SCL Rise
                    if (sys_cnt == PHASE_75) sda_out <= 1'b1; // SDA Rises while SCL is high (STOP condition)
                end
            endcase
        end
    end

endmodule
