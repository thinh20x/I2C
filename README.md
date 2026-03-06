mode standard 100Khz , 10uS, clk đầu vào 12Mhz, Tổng số  sys_cnt cho 1 chu kỳ SCL là: 12MHz / 100kHz = 120 .
t_HIGH (Min 4.0 µs): Thời gian SCL ở mức cao.
t_HD;STA} (Min 4.0 µs): Thời gian giữ (hold time) sau điều kiện START. Sau khoảng này, xung clock đầu tiên mới được phát.

Dùng hàng đợi lệnh (Command FIFO) - Chuyên nghiệpĐây là cách các IP Core lớn (như của Synopsys hay Cadence) thường làm. Bạn đẩy các "lệnh" vào một hàng đợi (FIFO), mỗi lệnh bao gồm dữ liệu và chỉ thị kèm theo.Ví dụ:Lệnh 1: [WRITE, 0x32, NO_STOP] (Ghi địa chỉ thanh ghi 0x32, không phát STOP).Lệnh 2: [READ, 2 bytes, STOP] (Đọc 2 byte, sau đó phát STOP).Khi đó FSM sẽ nhìn vào "Chỉ thị kèm theo" (Instruction bits):Tại CHECK_ACK_DATA, FSM kiểm tra lệnh tiếp theo trong FIFO. Nếu lệnh tiếp theo có bit START được set mà không có bit STOP trước đó $\to$ Tự động chuyển sang REPEATED_START. 





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


•	 (0-120): Đếm xem chúng ta đang ở vị trí nào của một chu kỳ SCL.
mỗi trạng thái tồn tại trong 120 sys_cnt

sys_cnt==0 0:  SCL=0

sys_cnt== 29 (25% chu kỳ): cập nhật data SDA.

sys_cnt ==59 (50% chu kỳ): SCL=1(high Z) 

Khi FSM của Master thả SCL lên 1 (High-Z) ở sys_cnt 59, FSM không được đếm sys_clk lên 60 ngay lập tức nếu scl_in vẫn đang bằng 0.

sys_cnt==89 (75% chu kỳ): SCL=1.lấy mẫu SDA để đọc bit hoặc đọc ACK
sys_cnt==119: Kết thúc 1 chu kỳ bit, reset sys_cnt = 0 

1.	IDLE: Trạng thái nghỉ, SDA = SCL =1.

  	Nếu FIFO_EMPTY == 0 (Có lệnh mới):
  	 reset đếm sys_cnt, 
  	 Đọc lệnh (Pop FIFO) lưu vào thanh ghi cmd_reg.Nếu cmd_reg[8] (START_EN) == 1 $\to$ Chuyển sang START.
  	Nếu không $\to$ Chuyển thẳng sang TX_BYTE hoặc RX_BYTE tùy vào cmd_reg[10].
  	
  	
3.	START: SDA==0, tạo thời gian delay 5uS tương đương sys_cnt== 59 thì reset đếm sys_cnt, bit_cnt=0 rồi  CHUYỂN QUA HOLD_TIME_DONE
4.	HOLD_TIME_DONE: SCL=0, , 
5.	SEND_ADDR:xét bit_cnt==7 thì gửi  xét bit_cnt==8 thì bit_cnt+1 rồi chuyển qua state CHECK_ACK_ADDR.bộ đếm tick đếm lần lượt đến tick thứ 3  thì  Gửi   bit thứ 6 địa chỉ (bit_cnt tăng 1),tick đếm đến 7 thì SCL=1, bộ đếm tick đếm đến 15 thì reset bộ đếm tick rồi chuyển qua state SEND_ADDR .
6.	CHECK_ACK_ADDR:  ở chu kỳ clock thứ 9.cứ đêm đến tick thứ 3 thì master high z Đợi Slave kéo SDA xuống thấp, tick thứ 11 lấy mẫy giữa xung cao SCL để đọc bit ACK, nếu SDA=1 (NACK) thì chuyển về stop.
   Nhánh rẽ: Nếu bit vừa gửi là 0 → chuyển sang WRITE_DATA.
  	Nhánh rẽ: Nếu bit vừa gửi là 1 → chuyển sang READ_DATA.
7.	WRITE_DATA: Gửi 8 bit dữ liệu
8.	CHEKC_ACK_DATA: Nhận ack

   Xong việc? $\to$ STOP.
   Muốn ghi tiếp? $\to$ WRITE_DATA.
   Muốn chuyển sang Đọc? (Combined mode) $\to$ REPEATED_START.
9.READ_DATA: Nhận 8 bit dữ liệu (Master thả chân SDA ở trạng thái High-Z).
10. SEND_ACK_NACK: Master gửi phản hồi cho Slave.Muốn đọc tiếp? $\to$ Gửi ACK (SDA=0) rồi về lại READ_DATA.Đọc xong byte cuối? $\to$ Gửi NACK (SDA=1) rồi sang STOP.
11.	REPEATED_START (Sr):Tạo điều kiện Start lần nữa (SCL cao, SDA 1 $\to$ 0) mà không qua STOP. Sau đó quay lại SEND_ADDR.
12.	STOP: Tạo điều kiện kết thúc. Quay về IDLE.
