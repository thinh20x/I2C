module i2c_master #(
    parameter SYS_CLK_FREQ = 50_000_000,
    parameter I2C_FREQ     = 100_000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [6:0]  device_addr,
    input  logic [7:0]  data_in,
    input  logic        start_trig,
    output logic        busy,
    output logic        ready,
    
    // I2C Physical Interface
    output logic        scl,
    inout  wire         sda
);
typedef enum logic [3:0] {
    IDLE,
    START,
    SEND_ADDR,
    ACK_ADDR,
    WRITE_DATA,
    READ_DATA,
    ACK_DATA,
    STOP
} state_t;
state_t current_state, next_state;
    // 1. Clock divider để tạo nhịp SCL
    // 2. FSM điều khiển các phase
    // 3. Logic xử lý SDA (Tri-state)
// Cách điều khiển chân SDA đúng chuẩn
assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;
assign sda_in = sda;
    
    // Gợi ý: Hãy dùng một biến đếm (counter) để xác định vị trí bit 
    // trong quá trình dịch chuyển (Shift register) từ 7 xuống 0.

endmodule
