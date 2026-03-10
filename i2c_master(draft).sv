hmodule i2c_master #(
    parameter SYS_CLK_FREQ = 12_000_000,
    parameter I2C_FREQ     = 100_000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,       // Thêm tín hiệu bắt đầu
    input  logic [6:0]  device_addr,
    input  logic [7:0]  data_in,
    input  logic        rw,          // 0: Write, 1: Read 
    
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
    //dùng 2 cấp đếm (Count -> Tick -> Phase)// Cách mới (làm tròn lên 8)để tần số bé hơn hơn an toàn
localparam int MAX_COUNT = (SYS_CLK_FREQ + (I2C_FREQ * 16) - 1) / (I2C_FREQ * 16);
  


    localparam int COUNT_WIDTH = $clog2(MAX_COUNT);
    logic [COUNT_WIDTH-1:0] count;
        
    logic [3:0] phase_cnt;
    logic tick_16x;
    
    // 1. Clock divider để tạo nhịp SCL
    always_ff @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            count<=0;
            tick_16x<=1'b0;
            phase_reg<=4'b0;
        end else if (count>=MAX_COUNT[COUNT_WIDTH-1:0]-1) begin
            count<=0;
            tick_16x<=1'b1;
            phase_reg <= phase_reg + 1; // Xoay vòng 0->1->2->3
           
        end else begin
            count<=count + 1'b1;
            tick_16x<=1'b0;
        end
    end

    // --- CÁC THANH GHI LOGIC ---
    logic [2:0]  bit_cnt;    // Đếm bit 0-7
    logic [1:0]  phase_cnt;  // Đếm pha 0-3 trong 1 chu kỳ SCL
    logic [8:0]  shift_reg;  // Chứa Addr + RW hoặc Data
    logic        sda_out, sda_out_en; // Logic điều khiển Tri-state
    
    // 2. FSM điều khiển các phase
    always @(posedge clk or negedge rst_n)begin
        if(~rst)begin
            current_state <= IDLE;
            phase_cnt     <= 0;
            bit_cnt       <= 0;
            shift_reg     <= 0;
            sda_out       <= 1;
            sda_out_en    <= 0; // Thả nổi SDA (High-Z)
            scl           <= 1; // Idle SCL = 1
            busy          <= 0;
            ready         <= 0;
            ack_error     <= 0;
            
        end else begin
            case (current_state)
                IDLE:begin
                end
                
                START:begin
                end
                
                SEND_ADDR:begin
                end
                
                ACK_ADDR:begin
                end
                
                WRITE_DATA:begin
                end
                
                READ_DATA:begin
                end
                
                ACK_DATA:begin
                end
                
                STOP:begin
                end
                
                default: next_state<=idle;
        end
    end
    // 3. Logic xử lý SDA (Tri-state)

// Logic Tri-state
    assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;
    
    // Input SDA để đọc ACK (Debounce/Sync nếu cần, ở đây làm đơn giản)
    logic sda_in_sync;
    assign sda_in_sync = sda;
    
    // Gợi ý: Hãy dùng một biến đếm (counter) để xác định vị trí bit 
    // trong quá trình dịch chuyển (Shift register) từ 7 xuống 0.

endmodule
