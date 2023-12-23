module IIC_M_Interface
#(
    parameter   SYS_CLOCK = 'd50_000_000, //系统时钟采用50MHz
    parameter   SCL_CLOCK = 'd400_000     //SCL总线时钟采用400kHz
)(
    input           clk,
    input           rst_n,

    input           cmd_vaild,
    input   [5:0]        cmd,
    input   [7:0]   w_data,
    output  reg     Trans_Done,
    output  reg [7:0]   r_data,

    output  iic_scl,
    inout   iic_sda
);
reg [7:0] state;
localparam  WR    = 6'b000001,	  //写请求      
            STATE = 6'b000010,	  //起始位请求
            RD    = 6'b000100,	  //读请求      
            STOP  = 6'b001000,	  //停止位请求
            ACK   = 6'b010000,	  //应答位请求
            NACK  = 6'b100000;	  //无应答请求
localparam  IDLE     = 8'b0000_0001,
            GEN_STA  = 8'b0000_0010,
            GEN_STO  = 8'b0000_0100,
            WR_DATA  = 8'b0000_1000,
            RD_DATA  = 8'b0001_0000,
            GEN_ACK  = 8'b0010_0000,
            GEN_NACK = 8'b0100_0000;
localparam  SCL_CNT_MAX = (SYS_CLOCK/SCL_CLOCK)/4;  //产生时钟SCL计数器最大值
reg [31:0]  base_cnt;
reg         base_cnt_en;
reg [31:0]  line_cnt;
reg         iic_scl_reg,iic_sda_oe,iic_sda_reg,ack_reg;
/***********************
IIC信号
**************************/
assign iic_scl = iic_scl_reg;
assign iic_sda = (iic_sda_oe)?(iic_sda_reg? 1'dz:1'b0):1'dz;
/*************************************************
base_cnt为系统时钟计数器，每次计数到最大值为1/4的IIC时钟周期，
同时输出base_cnt_end_edge为计数完成一次的最后一个数；
line_cnt为IIC时钟计数器，计数四个表示一个IIC时钟周期，
起始位，停止位，检测位都是一个IIC时钟，计数为0-3，
而读写数据为八个IIC时钟，计数为0-31.
************************************************/
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              base_cnt_en <= 1'b0;
    else if(cmd_vaild)      base_cnt_en <= 1'b1;
    else if(state == IDLE)  base_cnt_en <= 1'b0;
    else                    base_cnt_en <= base_cnt_en;
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              base_cnt <= 'd0;
    else if(base_cnt_en)  begin
        if(base_cnt < SCL_CNT_MAX)  
            base_cnt <= base_cnt + 1'b1;
        else                
            base_cnt <= 'd0;
    end
    else                    base_cnt <= 'd0;
end
assign base_cnt_end_edge = (base_cnt==SCL_CNT_MAX)?1'b1:1'b0;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              line_cnt <= 'd0;
    else if(state==GEN_STA || state==GEN_STO || state==GEN_ACK || state==GEN_NACK) begin
    if(base_cnt_end_edge )          begin
            if(line_cnt == 3 )      line_cnt <= 'd0;
            else                    line_cnt <= line_cnt + 1'b1;
    end
    else                            line_cnt <= line_cnt;
    end
    else if(state==WR_DATA ||state==RD_DATA) begin
    if(base_cnt_end_edge )          begin
            if(line_cnt == 31)    line_cnt <= 'd0;
            else                    line_cnt <= line_cnt + 1'b1;
    end
    else                            line_cnt <= line_cnt;
end
end
/**********************************************
cmd命令由 STATE,WR,RD,STOP四个基本命令按位或(|)得到，
在进行状态跳转的时候，使用cmd与基本命令按位与(&)跳转。
cmd命令本质是在读或者写一个字节的基础上，添加起始停止以及ACK信号，
写时序用到的跳转格式    对应的命令
1.STA+WR+ACK            cmd = STA | WR
2.WR+ACK                cmd = WR
3.WR+ACK+STP            cmd = WR | STO
读时序增加
4.RD+NACK+STP           cmd = RD | STO
**********************************************/
always@(posedge clk or negedge rst_n) begin
        if(!rst_n)  begin
            state <= 'b0 ;
        end else begin
            case(state)
            IDLE    :   if(cmd_vaild) begin
                                if(cmd & STATE)         state <= GEN_STA;
                                else if(cmd & WR)       state <= WR_DATA;  
                                else if(cmd & RD)       state <= RD_DATA; 
                                else                    state <= IDLE;
                        end else                        state <= IDLE;
            GEN_STA :   if(base_cnt_end_edge && line_cnt ==3) begin
                            if(cmd & WR)        state <= WR_DATA;
                            else                state <= IDLE;
                        end else begin
                                                state <= GEN_STA;
                        end
            GEN_STO :   if(base_cnt_end_edge && line_cnt ==3) begin
                                                state <= IDLE;
                        end else begin
                                                state <= GEN_STO;
                        end
            WR_DATA :   if(base_cnt_end_edge && line_cnt ==31) 
                                                state <= GEN_ACK;
                        else                    
                                                state <= WR_DATA;
            RD_DATA :   if(base_cnt_end_edge && line_cnt ==31) 
                                                state <= GEN_NACK;
                        else                    
                                                state <= RD_DATA;
            GEN_ACK :   if(base_cnt_end_edge && line_cnt ==3) begin
                            if(cmd & STOP)      state <= GEN_STO;
                            else                state <= IDLE;
                        end else begin
                                                state <= GEN_ACK;
                        end
            GEN_NACK:   if(base_cnt_end_edge && line_cnt ==3) begin
                            if(cmd & STOP)      state <= GEN_STO;
                            else                state <= IDLE;
                        end else begin
                                                state <= GEN_NACK;
                        end
            default:state <= IDLE;
        endcase
        end   
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)                  iic_scl_reg <= 1'b1;
    else if ( state==GEN_STA || state==GEN_STO || state==GEN_ACK || state==GEN_NACK ) begin
            if(line_cnt == 'd0)             iic_scl_reg <= 1'b0;   
            else if (line_cnt == 'd2)       iic_scl_reg <= 1'b1;
            else                            iic_scl_reg <= iic_scl_reg;
    end else if(state==WR_DATA ||state==RD_DATA) begin
            case(line_cnt)
            0,4,8,12,16,20,24,28    :       iic_scl_reg <= 1'b0;
            2,6,10,14,18,22,26,30   :       iic_scl_reg <= 1'b1;
            default:                        iic_scl_reg <= iic_scl_reg;
            endcase
    end else begin
                                            iic_scl_reg <= iic_scl_reg;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              iic_sda_oe  <= 'b1;
    else if (state == GEN_ACK || state == RD_DATA)              iic_sda_oe  <= 'b0;
    else                                    iic_sda_oe  <= 'b1;
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              iic_sda_reg <= 'b1;
    else if(state == GEN_STA ) begin
            if(line_cnt == 'd3)             iic_sda_reg <= 'b0;
            else                            iic_sda_reg <= iic_sda_reg;
    end else if(state == GEN_STO ) begin
            if(line_cnt == 'd3)             iic_sda_reg <= 'b1;
            else                            iic_sda_reg <= iic_sda_reg;
    end else if(state == GEN_ACK ) begin
                                            iic_sda_reg <= iic_sda_reg;
    end else if(state == GEN_NACK ) begin
            if(line_cnt == 'd1)             iic_sda_reg <= 'b1;
            else                            iic_sda_reg <= iic_sda_reg;
    end if (state==WR_DATA ) begin
            case(line_cnt)
                1 :  iic_sda_reg <= w_data[7];
                5 :  iic_sda_reg <= w_data[6];
                9 :  iic_sda_reg <= w_data[5];
                13 : iic_sda_reg <= w_data[4];
                17 : iic_sda_reg <= w_data[3];
                21 : iic_sda_reg <= w_data[2];
                25 : iic_sda_reg <= w_data[1];
                29 : iic_sda_reg <= w_data[0];
            default:iic_sda_reg <= iic_sda_reg;
            endcase
    end if (state==RD_DATA ) begin
            if(base_cnt_end_edge)begin
                case(line_cnt)
                    3  :  r_data <= {r_data[6:0],iic_sda};
                    7  :  r_data <= {r_data[6:0],iic_sda};
                    11  :  r_data <= {r_data[6:0],iic_sda};
                    15  :  r_data <= {r_data[6:0],iic_sda};  
                    19  :  r_data <= {r_data[6:0],iic_sda};
                    23  :  r_data <= {r_data[6:0],iic_sda};
                    27  :  r_data <= {r_data[6:0],iic_sda};
                    31  :  r_data <= {r_data[6:0],iic_sda};  
                default:  r_data <= r_data;
            endcase
            end
            else            r_data <= r_data;
            
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              ack_reg <= 'b1;
    else if(state == GEN_ACK && line_cnt == 'd3) 
                            ack_reg <= iic_sda;
    else                    ack_reg <= 'b1;     
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)              Trans_Done <= 'b0;
    else if(state == GEN_ACK && line_cnt == 'd3 && base_cnt_end_edge)   
                            Trans_Done <= 'b1;
    else if(state == GEN_STO && line_cnt == 'd3 && base_cnt_end_edge)   
                            Trans_Done <= 'b1;
    else                    Trans_Done <= 'b0;
end
endmodule