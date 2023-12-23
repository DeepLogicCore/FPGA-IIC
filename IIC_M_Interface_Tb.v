`timescale 1ns/1ns
module IIC_M_Interface_Tb();
    reg Clk;
	reg Rst_n;
	reg [5:0] Cmd;
	reg Go;
	wire [7:0] Rx_DATA;
	reg [7:0] Tx_DATA;
	wire Trans_Done;
	wire i2c_sclk;
	wire i2c_sdat;

pullup PUP(i2c_sdat);
	
localparam 
		WR   = 6'b000001,   //写请求
		STA  = 6'b000010,   //起始位请求
		RD   = 6'b000100,   //读请求
		STO  = 6'b001000,   //停止位请求
		ACK  = 6'b010000,   //应答位请求
		NACK = 6'b100000;   //无应答请求
    
M24LC04B M24LC04B(
		.A0(0), 
		.A1(0), 
		.A2(0), 
		.WP(0), 
		.SDA(i2c_sdat), 
		.SCL(i2c_sclk), 
		.RESET(~Rst_n)
	);
	
	always #10 Clk = ~Clk;
	
	initial begin
        Clk = 1;
	    Rst_n = 0;
	    Cmd = 6'b000000;
	    Go = 0;
	    Tx_DATA = 8'd0;
	    #2001;
		Rst_n = 1;
		#2000;
		
		//写数据操作，往EEPROM器件的B1地址写数据DA
		//第一次：起始位+EEPROM器件地址（7位）+写方向（1位）
		Cmd = STA | WR;
	    Go = 1;
	    Tx_DATA = 8'hA0 | 8'd0;//写方向
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #800;
	    
	    //第二次：写8位EEPROM的寄存器地址
	    Cmd = WR;
	    Go = 1;
	    Tx_DATA = 8'hB1;//写地址B1
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    //第三次：写8位数据 + 停止位
	    Cmd = WR | STO;
	    Go = 1;
	    Tx_DATA = 8'hda;//写数据DA
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    #5000000; //仿真模型的两次操作时间间隔
	    //读数据操作，从EEPROM器件的B1地址读数据
	    //第一次：起始位+EEPROM器件地址（7位）+写方向（1位）
		Cmd = STA | WR;
	    Go = 1;
	    Tx_DATA = 8'hA0 | 8'd0;//写方向
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    //第二次：写8位EEPROM的寄存器地址
	    Cmd = WR;
	    Go = 1;
	    Tx_DATA = 8'hB1;//写地址B1
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    //第三次：起始位+EEPROM器件地址（7位）+读方向（1位）
		Cmd = STA | WR;
	    Go = 1;
	    Tx_DATA = 8'hA0 | 8'd1;//读方向
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    //第四次：读8位数据 + 停止位
	    Cmd = RD | STO;
	    Go = 1;
	    @ (posedge Clk);
	    Go = 0;
	    @ (posedge Trans_Done);
	    #200;
	    
	    #2000;
		#4000;
	    $stop;
	end


IIC_M_Interface IIC_M_Interface_U(
                .clk         (Clk),
                .rst_n       (Rst_n),
                .cmd_vaild   (Go),  
                .cmd         (Cmd),
                .w_data      (Tx_DATA),
                .Trans_Done  (Trans_Done),
                .r_data      (Rx_DATA),
                .iic_scl     (i2c_sclk),
                .iic_sda     (i2c_sdat)
);
endmodule