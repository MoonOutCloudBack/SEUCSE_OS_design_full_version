// vga naive 模块，用来产生彩条屏幕
// https://www.cnblogs.com/liujinggang/p/9690504.html


module mfp_ahb_vga_naive(
    input                   I_clk   ,       // 系统 50MHz 时钟
    input                   I_rst_n ,       // 系统复位
    input           [12287:0]  I_string,    // 希望显示的字符串
    output  reg     [3:0]    O_red   ,      // VGA 红色分量
    output  reg     [3:0]    O_green ,      // VGA 绿色分量
    output  reg     [3:0]    O_blue  ,      // VGA 蓝色分量
    output                  O_hs    ,       // VGA 行同步信号
    output                  O_vs            // VGA 场同步信号
    // 共 14 个输出信号
);
    
    
    // 关于 VGA 的时序信号：
    // 可参考 https://blog.csdn.net/u014586651/article/details/121850814
    // 行时序：
        // 包括：行同步 (Hor Sync)、行消隐 (Hor Back Porch)、行视频有效 (Hor Active Video)、行前肩 (Hor Front Porch)
        // 在一个行周期内，行时序输出首先在 行同步 时间内置零，然后保持 1。
        // 数据输出：首先等一个 行消隐，然后在 行视频有效 时间段内输出，最后等一个 行前肩
    // 场时序：
        // 包括：场同步 (Ver Sync)、场消隐 (Ver Back Porch)、场视频有效 (Ver Active Video)、场前肩 (Ver Front Porch)
        // 在一个场周期内，场时序输出首先在 场同步 时间内置零，然后保持 1。
        // 数据输出：首先等一个 场消隐，然后在 场视频有效 时间段内输出，最后等一个 场前肩
    // 需要注意：
        // 行时序以 像素 为单位， 场时序以 行 为单位
        // 分辨率为 640*480 时，要用 25.275 MHz 的时钟
        // 
    
    // 分辨率为 640*480 时，行时序各个参数定义
    parameter       C_H_SYNC_PULSE      =   96  , 
                    C_H_BACK_PORCH      =   48  ,
                    C_H_ACTIVE_TIME     =   640 ,
                    C_H_FRONT_PORCH     =   16  ,
                    C_H_LINE_PERIOD     =   800 ;

    // 分辨率为 640*480 时，场时序各个参数定义               
    parameter       C_V_SYNC_PULSE      =   2   , 
                    C_V_BACK_PORCH      =   33  ,
                    C_V_ACTIVE_TIME     =   480 ,
                    C_V_FRONT_PORCH     =   10  ,
                    C_V_FRAME_PERIOD    =   525 ;
                    
    parameter       C_COLOR_BAR_WIDTH   =   C_H_ACTIVE_TIME / 8  ;  

    reg [11:0]      R_h_cnt         ; // 行时序计数器
    reg [11:0]      R_v_cnt         ; // 列时序计数器
    reg             R_clk_25M       ; // 25MHz 像素时钟

    wire            W_active_flag   ; // 激活标志，当这个信号为 1 时 RGB 的数据可以显示在屏幕上
    
    //////////////////////////////////////////////////////////////////
    // 功能： 产生 25MHz 的像素时钟 R_clk_25M
    //////////////////////////////////////////////////////////////////
    always @(posedge I_clk or negedge I_rst_n) // 输入的 50 MHz I_clk 的上升沿
    begin
        if(!I_rst_n) // reset
            R_clk_25M   <=  1'b0        ;
        else
            R_clk_25M   <=  ~R_clk_25M  ;     // 每到上升沿才反转，50 MHz -> 25 MHz
    end

    //////////////////////////////////////////////////////////////////
    // 功能：产生行时序计数器 R_h_cnt
    //////////////////////////////////////////////////////////////////
    always @(posedge R_clk_25M or negedge I_rst_n)
    begin
        if(!I_rst_n) // reset
            R_h_cnt <=  12'd0   ;
        else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1) // 计数到最大值了，重新开始
            R_h_cnt <=  12'd0   ;
        else
            R_h_cnt <=  R_h_cnt + 1'b1  ;                
    end                

    // 产生行时序输出 O_hs，C_H_SYNC_PULSE 内要置零
    assign O_hs =   (R_h_cnt < C_H_SYNC_PULSE) ? 1'b0 : 1'b1    ; 
    //////////////////////////////////////////////////////////////////


    //////////////////////////////////////////////////////////////////
    // 功能：产生场时序计数器 R_v_cnt
    //////////////////////////////////////////////////////////////////
    always @(posedge R_clk_25M or negedge I_rst_n)
    begin
        if(!I_rst_n) // reset
            R_v_cnt <=  12'd0   ;
        else if(R_v_cnt == C_V_FRAME_PERIOD - 1'b1) // 计数到最大值了，重新开始
            R_v_cnt <=  12'd0   ;
        else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1) // 一行完成了，R_v_cnt++
            R_v_cnt <=  R_v_cnt + 1'b1  ;
        else // 不变
            R_v_cnt <=  R_v_cnt ;                        
    end                

    // 产生行时序输出 O_vs，C_V_SYNC_PULSE 内要置零
    assign O_vs =   (R_v_cnt < C_V_SYNC_PULSE) ? 1'b0 : 1'b1    ; 
    //////////////////////////////////////////////////////////////////  


    // 产生 是否可以输出 RGB: W_active_flag 
    // 可以输出：R_h_cnt 在行消隐、行前肩之间，且 R_v_cnt 在场消隐、场前肩之间
    assign W_active_flag =  (R_h_cnt >= (C_H_SYNC_PULSE + C_H_BACK_PORCH                  ))  &&
                            (R_h_cnt <= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_H_ACTIVE_TIME))  && 
                            (R_v_cnt >= (C_V_SYNC_PULSE + C_V_BACK_PORCH                  ))  &&
                            (R_v_cnt <= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_V_ACTIVE_TIME))  ;      
    //////////////////////////////////////////////////////////////////                 


    //////////////////////////////////////////////////////////////////
    // 功能：把显示器屏幕分成8个纵列，每个纵列的宽度是80
    //////////////////////////////////////////////////////////////////
    always @(posedge R_clk_25M or negedge I_rst_n)
    begin
        if(!I_rst_n) // reset
            begin
                O_red   <=  4'b0000   ;
                O_green <=  4'b0000   ;
                O_blue  <=  4'b0000   ; 
            end
        else if(W_active_flag)     // 根据行计数 R_h_cnt 来判断，是简单的赋值逻辑
            begin
                if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH)) // 红色彩条
                    begin
                        O_red   <=  4'b1111    ; // 红色彩条把红色分量全部给1，绿色和蓝色给0
                        O_green <=  4'b0000    ;
                        O_blue  <=  4'b0000    ;
                    end
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*2)) // 绿色彩条
                    begin
                        O_red   <=  4'b0000    ;
                        O_green <=  4'b1111    ; // 绿色彩条把绿色分量全部给1，红色和蓝色分量给0
                        O_blue  <=  4'b0000    ;
                    end 
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*3)) // 蓝色彩条
                    begin
                        O_red   <=  4'b0000    ;
                        O_green <=  4'b0000    ;
                        O_blue  <=  4'b1111    ; // 蓝色彩条把蓝色分量全部给1，红色和绿分量给0
                    end 
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*4)) // 白色彩条
                    begin
                        O_red   <=  4'b1111    ; // 白色彩条是有红绿蓝三基色混合而成
                        O_green <=  4'b1111    ; // 所以白色彩条要把红绿蓝三个分量全部给1
                        O_blue  <=  4'b1111    ;
                    end 
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*5)) // 黑色彩条
                    begin
                        O_red   <=  4'b0000    ; // 黑色彩条就是把红绿蓝所有分量全部给0
                        O_green <=  4'b0000    ;
                        O_blue  <=  4'b0000    ;
                    end 
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*6)) // 黄色彩条
                    begin
                        O_red   <=  4'b1111    ; // 黄色彩条是有红绿两种颜色混合而成
                        O_green <=  4'b1111    ; // 所以黄色彩条要把红绿两个分量给1
                        O_blue  <=  4'b0000    ; // 蓝色分量给0
                    end 
                else if(R_h_cnt < (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_COLOR_BAR_WIDTH*7)) // 紫色彩条
                    begin
                        O_red   <=  4'b1111    ; // 紫色彩条是有红蓝两种颜色混合而成
                        O_green <=  4'b0000    ; // 所以紫色彩条要把红蓝两个分量给1
                        O_blue  <=  4'b1111    ; // 绿色分量给0
                    end 
                else                              // 青色彩条
                    begin
                        O_red   <=  4'b0000    ; // 青色彩条是由蓝绿两种颜色混合而成
                        O_green <=  4'b1111    ; // 所以青色彩条要把蓝绿两个分量给1
                        O_blue  <=  4'b11111    ; // 红色分量给0
                    end                   
            end
        else
            begin
                O_red   <=  4'b0000    ;
                O_green <=  4'b0000    ;
                O_blue  <=  4'b0000    ; 
            end           
    end

        
endmodule



















