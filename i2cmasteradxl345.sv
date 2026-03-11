// ============================================================================
// MODULE 1: CHỐNG NHIỄU VÀ TẠO XUNG NÚT NHẤN (CHO NÚT NHẤN MỨC 0 / ACTIVE-LOW)
// ============================================================================
module button_debounce (
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,    // Tín hiệu vào từ board (bình thường 1, nhấn là 0)
    output wire btn_pulse  // Xung ra cho FSM (bình thường 0, có sự kiện là 1)
);
    reg [15:0] count;
    reg btn_sync_0, btn_sync_1, btn_state;
    reg btn_prev;

    // Đồng bộ hóa (Giống như cũ)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync_0 <= 1'b1; // Khởi tạo mức 1 (trạng thái nhả nút)
            btn_sync_1 <= 1'b1;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // Bộ đếm Debounce (Giống như cũ, nhưng giá trị khởi tạo của btn_state là 1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 16'd0;
            btn_state <= 1'b1; // Mặc định là mức 1
        end else begin
            if (btn_sync_1 != btn_state) begin
                count <= count + 1'b1;
                if (count == 16'hFFFF) begin
                    btn_state <= btn_sync_1;
                    count <= 16'd0;
                end
            end else begin
                count <= 16'd0;
            end
        end
    end

    // Phát hiện sườn xuống (Falling Edge Detector)
    // Nghĩa là: Trạng thái trước đó là 1 (nhả), trạng thái hiện tại là 0 (đã nhấn ổn định)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_prev <= 1'b1;
        else btn_prev <= btn_state;
    end
    
    // Tạo xung mức CAO (1) khi phát hiện sự kiện ấn nút
    assign btn_pulse = (btn_prev == 1'b1 && btn_state == 1'b0); 
    
endmodule
