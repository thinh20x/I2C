SCL: do master phát điều khiển dữ liệu(lưu ý dùng chân tốc độ đủ cao >100Khz để cấu hình)
SDA: đường dữ liệu 2 chiều 
// Ví dụ mô tả chân SDA trong Verilog
//  Chỉ kéo xuống 0 khi cần, còn lại thả High-Z
assign SDA = (sda_out_en == 1'b1 && sda_out_reg == 1'b0) ? 1'b0 : 1'bz;
Open-Drain, vi mạch I2C tuyệt đối không bao giờ được phép chủ động xuất mức 1 (High) ra đường dây.
 Để truyền bit 1, bạn không "ghi số 1", mà bạn "thả đường dây ra" (đưa về High-Z).
assign sda_in = SDA; // Luôn đọc về để kiểm tra trạng thái bus

tạo bộ chi xung clk counter: •	Tick (16x): Cứ N chu kỳ Clock thì nháy lên 1 lần.
•	Phase (0-15): Đếm xem chúng ta đang ở vị trí nào của một chu kỳ SCL.
mỗi trạng thái tồn tại trong 16 tick
sử dụng phase để ra lệnh cho chân SDA và SCL dựa trên trạng thái hiện tại của FSM.
o	Phase 0-3: Thời gian an toàn để thay đổi SDA (vì SCL chắc chắn đang thấp).
o	Phase 8-11: Thời gian an toàn để Đọc (Sample) SDA (vì SCL chắc chắn đang cao và ổn định).


1.	IDLE: Trạng thái nghỉ, SDA = SCL =1.en=1 thì chuyển qua start
2.	START: Kéo SDA xuống trước SCL.sda=0, sau đó scl = ,0 bắt đầu chu kì clk
3.	SEND_ADDR_W: cứ SCL low thì lần lượt Gửi 7 bit địa chỉ + bit R/W = 0 (Ghi).cnt chu kỳ bit tăng đến từ 0 đến 7
4.	WAIT_ACK:  ở chu kỳ clock thứ 9.master high z Đợi Slave kéo SDA xuống thấp, nếu SDA=1 thì chuyển về stop
5.	SEND_REG: Gửi địa chỉ thanh ghi muốn đọc (ví dụ 0x32).
6.	WAIT_ACK 
7.	REPEATED_START (Sr):nếu trước đó chưa có stop thì nhảy vào repeat start Tạo điều kiện Start lần nữa mà không giải phóng bus.
8.	SEND_ADDR_R: Gửi 7 bit địa chỉ + bit R/W = 1 (Đọc).
9.	wait ack
10.	READ_DATA: Nhận 8 bit dữ liệu từ Slave.
11.	SEND_ACK/NACK: Master gửi ACK nếu muốn đọc tiếp, hoặc NACK nếu là byte cuối cùng.(đọc liên tiếp nhiều byte bằng auto-increment register pointer)
12.	STOP: Kéo SDA từ thấp lên cao khi SCL đang cao để kết thúc.
