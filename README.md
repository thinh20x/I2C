mode standard 100Khz , 10uS
t_LOW (Min 4.7 µs): Thời gian SCL ở mức thấp.
t_HIGH (Min 4.0 µs): Thời gian SCL ở mức cao.
t_HD;STA} (Min 4.0 µs): Thời gian giữ (hold time) sau điều kiện START. Sau khoảng này, xung clock đầu tiên mới được phát.

SCL: do master phát điều khiển dữ liệu(lưu ý dùng chân tốc độ đủ cao >100Khz để cấu hình)
SDA: đường dữ liệu 2 chiều 
// Ví dụ mô tả chân SDA trong Verilog
//  Chỉ kéo xuống 0 khi cần, còn lại thả High-Z
assign SDA = (sda_out_en == 1'b1 && sda_out_reg == 1'b0) ? 1'b0 : 1'bz;
assign SCL = (scl_out_en == 1'b1 && scl_out_reg == 1'b0) ? 1'b0 : 1'bz;
assign scl_in = SCL;// Luôn đọc về để kiểm tra trạng thái bus
Nếu phát 1 mà đọc về 0, nghĩa là đã thua trong việc tranh chấp bus và phải rút lui về trạng thái IDLE.

Open-Drain, vi mạch I2C tuyệt đối không bao giờ được phép chủ động xuất mức 1 (High) ra đường dây.
 Để truyền bit 1, bạn không "ghi số 1", mà bạn "thả đường dây ra" (đưa về High-Z).


tạo Tick (gấp 16 lần SCl): Cứ N chu kỳ Clock thì nháy lên 1 lần.
•	Phase (0-15): Đếm xem chúng ta đang ở vị trí nào của một chu kỳ SCL.
mỗi trạng thái tồn tại trong 16 tick

Phase 0: thay đổi cập nhật giá trị SDA, SCL=0

Phase 4 (25% chu kỳ): kéo SCL=1.

Phase 8 (50% chu kỳ): SCL=1 để đọc dữ liệu



Phase 12 (75% chu kỳ): kéo SCL xuống 0

1.	IDLE: Trạng thái nghỉ, SDA = SCL =1.en=1 thì chuyển qua start
2.	START: .Thả SDA=1, SCL=1 -> Kéo SDA=0, DELAY 5US CHUYỂN QUA HOLD_TIME
3.	HOLD_TIME: SCL=0
4.	SEND_ADDR: cứ SCL low thì lần lượt Gửi 7 bit địa chỉ + bit R/W = 0 (Ghi).bộ đếm bit tăng đến từ 0 đến 7
5.	CHECK_ACK_ADDR:  ở chu kỳ clock thứ 9.master high z Đợi Slave kéo SDA xuống thấp, lấy mẫy giữa xung cao SCL để đọc bit ACK, nếu SDA=1 (NACK) thì chuyển về stop.
   Nhánh rẽ: Nếu bit vừa gửi là 0 → chuyển sang WRITE_DATA.
  	Nhánh rẽ: Nếu bit vừa gửi là 1 → chuyển sang READ_DATA.
7.	WRITE_DATA: Gửi 8 bit dữ liệu
8.	CHEKC_ACK_DATA: Nhận ack

   Xong việc? $\to$ STOP.
   Muốn ghi tiếp? $\to$ WRITE_DATA.
   Muốn chuyển sang Đọc? (Combined mode) $\to$ REPEATED_START.
10.	REPEATED_START (Sr):nếu trước đó chưa có stop thì nhảy vào repeat start Tạo điều kiện Start lần nữa mà không giải phóng bus.
11.	SEND_ADDR_R: Gửi 7 bit địa chỉ + bit R/W = 1 (Đọc).
12.	wait ack
13.	READ_DATA: Nhận 8 bit dữ liệu từ Slave.
14.	SEND_ACK/NACK: Master gửi ACK nếu muốn đọc tiếp, hoặc NACK nếu là byte cuối cùng.(đọc liên tiếp nhiều byte bằng auto-increment register pointer)
15.	STOP: SDA chuyển từ LOW lên HIGH khi SCL đang HIGH. Bạn cần đảm bảo SDA đã ở mức thấp trước khi SCL lên cao, sau đó mới thả SDA ra.
