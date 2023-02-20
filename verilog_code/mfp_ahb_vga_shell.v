// 用来显示 shell 的 vga 模块
// 魔改了 https://www.cnblogs.com/liujinggang/p/9690504.html 的框架


module mfp_ahb_vga_shell(
    input                   I_clk   ,       // 系统 50MHz 时钟
    input                   I_rst_n ,       // 系统复位
    input           [32:0]  I_data  ,       // 32 位数据，[15:8] 是 cursor，[7:0] 是 ASCII
    output  reg     [3:0]   O_red   ,       // VGA 红色分量
    output  reg     [3:0]   O_green ,       // VGA 绿色分量
    output  reg     [3:0]   O_blue  ,       // VGA 蓝色分量
    output  reg             O_hs    ,       // VGA 行同步信号
    output  reg             O_vs            // VGA 场同步信号
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


    // 关于 VGA 同步 shell 输出：
        // 字模：
            // 一行有 640 个像素，要摆 64 个字符，一个字符 10 像素
            // 一列有 480 个像素，要摆 24 个字符，一个字符 20 像素
            // 因此，使用比例为 1：2 的字模
        // 判断当前为哪个字符：
            // 用行计数器得到 x 坐标，场计数器得到 y 坐标，直接索引输入字符串
        // 输出字模：
            // 只找到了 8 * 16 的字模，因此边缘留白
            // 用像素在 10 * 20 字符里的 x y 坐标，索引字模 parameter

    
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
                    
    reg [11:0]      R_h_cnt         ; // 行时序计数器
    reg [11:0]      R_v_cnt         ; // 列时序计数器
    reg             R_clk_25M       ; // 25MHz 像素时钟

    reg             W_active_flag   ; // 激活标志，当这个信号为 1 时 RGB 的数据可以显示在屏幕上

    // 记录屏幕的 64 * 24 * 8 字符串
    reg [12287:0]   R_screen_string ;
    
    // 为了输出 shell 的自定义 reg 变量
    reg [5:0]       R_char_h_cnt    ; // 打印字符的当前行坐标
    reg [4:0]       R_char_v_cnt    ; // 打印字符的当前列坐标
    reg [7:0]       R_now_ascii     ; // 打印字符的 8 位 ASCII 码
    reg [3:0]       R_char_h_detail ; // 打印字符 字模的当前行坐标
    reg [4:0]       R_char_v_detail ; // 打印字符 字模的当前列坐标

    // 133 * 16 * 8 字模的 parameter
    reg [127:0] C_ascii_character [133:0];


    //////////////////////////////////////////////////////////////////
    // 功能： 维护记录屏幕的 64 * 24 * 8 字符串 R_screen_string
    //////////////////////////////////////////////////////////////////
    always @(posedge I_clk or negedge I_rst_n) // 输入的 50 MHz I_clk 的上升沿
    begin
        if(!I_rst_n) // reset
            R_screen_string                        <=  12287'b0    ;
        else // I_data[15:8] 是 cursor，I_data[7:0] 是 ASCII
            R_screen_string[8 * I_data[15:8] -: 8] <=  I_data[7:0] ;
    end
    //////////////////////////////////////////////////////////////////
    

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


    
    always @(posedge R_clk_25M or negedge I_rst_n)
    begin
        //////////////////////////////////////////////////////////////////
        // 功能：产生行时序计数器 R_h_cnt
        //////////////////////////////////////////////////////////////////
        begin
            if(!I_rst_n) // reset
                R_h_cnt <=  12'd0   ;
            else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1) // 计数到最大值了，重新开始
                R_h_cnt <=  12'd0   ;
            else
                R_h_cnt <=  R_h_cnt + 1'b1  ;
            // 产生行时序输出 O_hs，C_H_SYNC_PULSE 内要置零
            O_hs = (R_h_cnt < C_H_SYNC_PULSE) ? 1'b0 : 1'b1    ;
        end
        //////////////////////////////////////////////////////////////////


        //////////////////////////////////////////////////////////////////
        // 功能：产生场时序计数器 R_v_cnt
        //////////////////////////////////////////////////////////////////
        begin
            if(!I_rst_n) // reset
                R_v_cnt <=  12'd0   ;
            else if(R_v_cnt == C_V_FRAME_PERIOD - 1'b1) // 计数到最大值了，重新开始
                R_v_cnt <=  12'd0   ;
            else if(R_h_cnt == C_H_LINE_PERIOD - 1'b1) // 一行完成了，R_v_cnt++
                R_v_cnt <=  R_v_cnt + 1'b1  ;
            else // 不变
                R_v_cnt <=  R_v_cnt ;
            // 产生行时序输出 O_vs，C_V_SYNC_PULSE 内要置零
            O_vs  =   (R_v_cnt < C_V_SYNC_PULSE) ? 1'b0 : 1'b1    ; 
        end
        //////////////////////////////////////////////////////////////////  


        //////////////////////////////////////////////////////////////////
        // 功能：产生 是否可以输出 RGB: W_active_flag 
        //////////////////////////////////////////////////////////////////
        begin // 可以输出：R_h_cnt 在行消隐、行前肩之间，且 R_v_cnt 在场消隐、场前肩之间
            W_active_flag = (R_h_cnt >= (C_H_SYNC_PULSE + C_H_BACK_PORCH                  ))  &&
                            (R_h_cnt <= (C_H_SYNC_PULSE + C_H_BACK_PORCH + C_H_ACTIVE_TIME))  && 
                            (R_v_cnt >= (C_V_SYNC_PULSE + C_V_BACK_PORCH                  ))  &&
                            (R_v_cnt <= (C_V_SYNC_PULSE + C_V_BACK_PORCH + C_V_ACTIVE_TIME))  ; 
        end
        //////////////////////////////////////////////////////////////////    


        //////////////////////////////////////////////////////////////////
        // 功能：赋值 ascii 字模
        //////////////////////////////////////////////////////////////////
        begin
            C_ascii_character[0] <= 128'h00000000000000000000000000000000;       //0x00
            C_ascii_character[1] <= 128'h00007E81A58181BD9981817E00000000;       //0x01
            C_ascii_character[2] <= 128'h00007EFFDBFFFFC3E7FFFF7E00000000;       //0x02
            C_ascii_character[3] <= 128'h000000006CFEFEFEFE7C381000000000;       //0x03
            C_ascii_character[4] <= 128'h0000000010387CFE7C38100000000000;       //0x04
            C_ascii_character[5] <= 128'h000000183C3CE7E7E718183C00000000;       //0x05
            C_ascii_character[6] <= 128'h000000183C7EFFFF7E18183C00000000;       //0x06
            C_ascii_character[7] <= 128'h000000000000183C3C18000000000000;       //0x07
            C_ascii_character[8] <= 128'hFFFFFFFFFFFFE7C3C3E7FFFFFFFFFFFF;       //0x08
            C_ascii_character[9] <= 128'h00000000003C664242663C0000000000;       //0x09
            C_ascii_character[10] <= 128'hFFFFFFFFFFC399BDBD99C3FFFFFFFFFF;       //0x0A
            C_ascii_character[11] <= 128'h00001E0E1A3278CCCCCCCC7800000000;       //0x0B
            C_ascii_character[12] <= 128'h00003C666666663C187E181800000000;       //0x0C
            C_ascii_character[13] <= 128'h00003F333F3030303070F0E000000000;       //0x0D
            C_ascii_character[14] <= 128'h00007F637F6363636367E7E6C0000000;       //0x0E
            C_ascii_character[15] <= 128'h0000001818DB3CE73CDB181800000000;       //0x0F
            C_ascii_character[16] <= 128'h0080C0E0F0F8FEF8F0E0C08000000000;       //0x10
            C_ascii_character[17] <= 128'h0002060E1E3EFE3E1E0E060200000000;       //0x11
            C_ascii_character[18] <= 128'h0000183C7E1818187E3C180000000000;       //0x12
            C_ascii_character[19] <= 128'h00006666666666666600666600000000;       //0x13
            C_ascii_character[20] <= 128'h00007FDBDBDB7B1B1B1B1B1B00000000;       //0x14
            C_ascii_character[21] <= 128'h007CC660386CC6C66C380CC67C000000;       //0x15
            C_ascii_character[22] <= 128'h0000000000000000FEFEFEFE00000000;       //0x16
            C_ascii_character[23] <= 128'h0000183C7E1818187E3C187E00000000;       //0x17
            C_ascii_character[24] <= 128'h0000183C7E1818181818181800000000;       //0x18
            C_ascii_character[25] <= 128'h0000181818181818187E3C1800000000;       //0x19
            C_ascii_character[26] <= 128'h0000000000180CFE0C18000000000000;       //0x1A
            C_ascii_character[27] <= 128'h00000000003060FE6030000000000000;       //0x1B
            C_ascii_character[28] <= 128'h000000000000C0C0C0FE000000000000;       //0x1C
            C_ascii_character[29] <= 128'h0000000000286CFE6C28000000000000;       //0x1D
            C_ascii_character[30] <= 128'h000000001038387C7CFEFE0000000000;       //0x1E
            C_ascii_character[31] <= 128'h00000000FEFE7C7C3838100000000000;       //0x1F
            C_ascii_character[32] <= 128'h00000000000000000000000000000000;       //0x20' '
            C_ascii_character[33] <= 128'h0000183C3C3C18181800181800000000;       //0x21'!'
            C_ascii_character[34] <= 128'h00666666240000000000000000000000;       //0x22'"'
            C_ascii_character[35] <= 128'h0000006C6CFE6C6C6CFE6C6C00000000;       //0x23'#'
            C_ascii_character[36] <= 128'h18187CC6C2C07C060686C67C18180000;       //0x24'$'
            C_ascii_character[37] <= 128'h00000000C2C60C183060C68600000000;       //0x25'%'
            C_ascii_character[38] <= 128'h0000386C6C3876DCCCCCCC7600000000;       //0x26'&'
            C_ascii_character[39] <= 128'h00303030600000000000000000000000;       //0x27'''
            C_ascii_character[40] <= 128'h00000C18303030303030180C00000000;       //0x28'('
            C_ascii_character[41] <= 128'h000030180C0C0C0C0C0C183000000000;       //0x29')'
            C_ascii_character[42] <= 128'h0000000000663CFF3C66000000000000;       //0x2A'*'
            C_ascii_character[43] <= 128'h000000000018187E1818000000000000;       //0x2B'+'
            C_ascii_character[44] <= 128'h00000000000000000018181830000000;       //0x2C'
            C_ascii_character[45] <= 128'h00000000000000FE0000000000000000;       //0x2D'-'
            C_ascii_character[46] <= 128'h00000000000000000000181800000000;       //0x2E'.'
            C_ascii_character[47] <= 128'h0000000002060C183060C08000000000;       //0x2F'/'
            C_ascii_character[48] <= 128'h0000386CC6C6D6D6C6C66C3800000000;       //0x30'0'
            C_ascii_character[49] <= 128'h00001838781818181818187E00000000;       //0x31'1'
            C_ascii_character[50] <= 128'h00007CC6060C183060C0C6FE00000000;       //0x32'2'
            C_ascii_character[51] <= 128'h00007CC606063C060606C67C00000000;       //0x33'3'
            C_ascii_character[52] <= 128'h00000C1C3C6CCCFE0C0C0C1E00000000;       //0x34'4'
            C_ascii_character[53] <= 128'h0000FEC0C0C0FC060606C67C00000000;       //0x35'5'
            C_ascii_character[54] <= 128'h00003860C0C0FCC6C6C6C67C00000000;       //0x36'6'
            C_ascii_character[55] <= 128'h0000FEC606060C183030303000000000;       //0x37'7'
            C_ascii_character[56] <= 128'h00007CC6C6C67CC6C6C6C67C00000000;       //0x38'8'
            C_ascii_character[57] <= 128'h00007CC6C6C67E0606060C7800000000;       //0x39'9'
            C_ascii_character[58] <= 128'h00000000181800000018180000000000;       //0x3A':'
            C_ascii_character[59] <= 128'h00000000181800000018183000000000;       //0x3B';'
            C_ascii_character[60] <= 128'h000000060C18306030180C0600000000;       //0x3C'<'
            C_ascii_character[61] <= 128'h00000000007E00007E00000000000000;       //0x3D'='
            C_ascii_character[62] <= 128'h0000006030180C060C18306000000000;       //0x3E'>'
            C_ascii_character[63] <= 128'h00007CC6C60C18181800181800000000;       //0x3F'?'
            C_ascii_character[64] <= 128'h0000007CC6C6DEDEDEDCC07C00000000;       //0x40'@'
            C_ascii_character[65] <= 128'h000010386CC6C6FEC6C6C6C600000000;       //0x41'A'
            C_ascii_character[66] <= 128'h0000FC6666667C66666666FC00000000;       //0x42'B'
            C_ascii_character[67] <= 128'h00003C66C2C0C0C0C0C2663C00000000;       //0x43'C'
            C_ascii_character[68] <= 128'h0000F86C6666666666666CF800000000;       //0x44'D'
            C_ascii_character[69] <= 128'h0000FE6662687868606266FE00000000;       //0x45'E'
            C_ascii_character[70] <= 128'h0000FE6662687868606060F000000000;       //0x46'F'
            C_ascii_character[71] <= 128'h00003C66C2C0C0DEC6C6663A00000000;       //0x47'G'
            C_ascii_character[72] <= 128'h0000C6C6C6C6FEC6C6C6C6C600000000;       //0x48'H'
            C_ascii_character[73] <= 128'h00003C18181818181818183C00000000;       //0x49'I'
            C_ascii_character[74] <= 128'h00001E0C0C0C0C0CCCCCCC7800000000;       //0x4A'J'
            C_ascii_character[75] <= 128'h0000E666666C78786C6666E600000000;       //0x4B'K'
            C_ascii_character[76] <= 128'h0000F06060606060606266FE00000000;       //0x4C'L'
            C_ascii_character[77] <= 128'h0000C6EEFEFED6C6C6C6C6C600000000;       //0x4D'M'
            C_ascii_character[78] <= 128'h0000C6E6F6FEDECEC6C6C6C600000000;       //0x4E'N'
            C_ascii_character[79] <= 128'h00007CC6C6C6C6C6C6C6C67C00000000;       //0x4F'O'
            C_ascii_character[80] <= 128'h0000FC6666667C60606060F000000000;       //0x50'P'
            C_ascii_character[81] <= 128'h00007CC6C6C6C6C6C6D6DE7C0C0E0000;       //0x51'Q'
            C_ascii_character[82] <= 128'h0000FC6666667C6C666666E600000000;       //0x52'R'
            C_ascii_character[83] <= 128'h00007CC6C660380C06C6C67C00000000;       //0x53'S'
            C_ascii_character[84] <= 128'h00007E7E5A1818181818183C00000000;       //0x54'T'
            C_ascii_character[85] <= 128'h0000C6C6C6C6C6C6C6C6C67C00000000;       //0x55'U'
            C_ascii_character[86] <= 128'h0000C6C6C6C6C6C6C66C381000000000;       //0x56'V'
            C_ascii_character[87] <= 128'h0000C6C6C6C6D6D6D6FEEE6C00000000;       //0x57'W'
            C_ascii_character[88] <= 128'h0000C6C66C7C38387C6CC6C600000000;       //0x58'X'
            C_ascii_character[89] <= 128'h0000666666663C181818183C00000000;       //0x59'Y'
            C_ascii_character[90] <= 128'h0000FEC6860C183060C2C6FE00000000;       //0x5A'Z'
            C_ascii_character[91] <= 128'h00003C30303030303030303C00000000;       //0x5B'['
            C_ascii_character[92] <= 128'h00000080C0E070381C0E060200000000;       //0x5C'\'
            C_ascii_character[93] <= 128'h00003C0C0C0C0C0C0C0C0C3C00000000;       //0x5D']'
            C_ascii_character[94] <= 128'h10386CC6000000000000000000000000;       //0x5E'^'
            C_ascii_character[95] <= 128'h00000000000000000000000000FF0000;       //0x5F'_'
            C_ascii_character[96] <= 128'h30301800000000000000000000000000;       //0x60'`'
            C_ascii_character[97] <= 128'h0000000000780C7CCCCCCC7600000000;       //0x61'a'
            C_ascii_character[98] <= 128'h0000E06060786C666666667C00000000;       //0x62'b'
            C_ascii_character[99] <= 128'h00000000007CC6C0C0C0C67C00000000;       //0x63'c'
            C_ascii_character[100] <= 128'h00001C0C0C3C6CCCCCCCCC7600000000;       //0x64'd'
            C_ascii_character[101] <= 128'h00000000007CC6FEC0C0C67C00000000;       //0x65'e'
            C_ascii_character[102] <= 128'h0000386C6460F060606060F000000000;       //0x66'f'
            C_ascii_character[103] <= 128'h000000000076CCCCCCCCCC7C0CCC7800;       //0x67'g'
            C_ascii_character[104] <= 128'h0000E060606C7666666666E600000000;       //0x68'h'
            C_ascii_character[105] <= 128'h00001818003818181818183C00000000;       //0x69'i'
            C_ascii_character[106] <= 128'h00000606000E06060606060666663C00;       //0x6A'j'
            C_ascii_character[107] <= 128'h0000E06060666C78786C66E600000000;       //0x6B'k'
            C_ascii_character[108] <= 128'h00003818181818181818183C00000000;       //0x6C'l'
            C_ascii_character[109] <= 128'h0000000000ECFED6D6D6D6C600000000;       //0x6D'm'
            C_ascii_character[110] <= 128'h0000000000DC66666666666600000000;       //0x6E'n'
            C_ascii_character[111] <= 128'h00000000007CC6C6C6C6C67C00000000;       //0x6F'o'
            C_ascii_character[112] <= 128'h0000000000DC66666666667C6060F000;       //0x70'p'
            C_ascii_character[113] <= 128'h000000000076CCCCCCCCCC7C0C0C1E00;       //0x71'q'
            C_ascii_character[114] <= 128'h0000000000DC7666606060F000000000;       //0x72'r'
            C_ascii_character[115] <= 128'h00000000007CC660380CC67C00000000;       //0x73's'
            C_ascii_character[116] <= 128'h0000103030FC30303030361C00000000;       //0x74't'
            C_ascii_character[117] <= 128'h0000000000CCCCCCCCCCCC7600000000;       //0x75'u'
            C_ascii_character[118] <= 128'h000000000066666666663C1800000000;       //0x76'v'
            C_ascii_character[119] <= 128'h0000000000C6C6D6D6D6FE6C00000000;       //0x77'w'
            C_ascii_character[120] <= 128'h0000000000C66C3838386CC600000000;       //0x78'x'
            C_ascii_character[121] <= 128'h0000000000C6C6C6C6C6C67E060CF800;       //0x79'y'
            C_ascii_character[122] <= 128'h0000000000FECC183060C6FE00000000;       //0x7A'z'
            C_ascii_character[123] <= 128'h00000E18181870181818180E00000000;       //0x7B'{'
            C_ascii_character[124] <= 128'h00001818181800181818181800000000;       //0x7C'|'
            C_ascii_character[125] <= 128'h0000701818180E181818187000000000;       //0x7D'}'
            C_ascii_character[126] <= 128'h000076DC000000000000000000000000;       //0x7E'~'
            C_ascii_character[127] <= 128'h0000000010386CC6C6C6FE0000000000;       //0x7F''
            C_ascii_character[128] <= 128'h00003C66C2C0C0C0C2663C0C067C0000;       //0x80
            C_ascii_character[129] <= 128'h0000CC0000CCCCCCCCCCCC7600000000;       //0x81
            C_ascii_character[130] <= 128'h000C1830007CC6FEC0C0C67C00000000;       //0x82
            C_ascii_character[131] <= 128'h0010386C00780C7CCCCCCC7600000000;       //0x83
            C_ascii_character[132] <= 128'h0000CC0000780C7CCCCCCC7600000000;
        end

        
        //////////////////////////////////////////////////////////////////
        // 功能：在 VGA 显示屏上同步 shell 的输出内容
        //////////////////////////////////////////////////////////////////
        begin
            if(!I_rst_n) // reset
                begin
                    O_red   <=  4'b0000   ;
                    O_green <=  4'b0000   ;
                    O_blue  <=  4'b0000   ; 
                end
            else if(W_active_flag)     // 如果现在可以输出 RGB
                begin
                    // 得到当前字符的 x 坐标
                    R_char_h_cnt    <=  (R_h_cnt - C_H_SYNC_PULSE - C_H_BACK_PORCH) / 10 ;
                    // 得到当前字符的 y 坐标
                    R_char_v_cnt    <=  (R_v_cnt - C_V_SYNC_PULSE - C_V_BACK_PORCH) / 20 ;
                    // 得到当前字符的 8 位 ascii 码
                    R_now_ascii     <=  R_screen_string[8 * (R_char_v_cnt * 64 + R_char_h_cnt + 1) - : 8]  ;
                    // 得到当前字符 字模的 x 坐标
                    R_char_h_detail <=  R_h_cnt - C_H_SYNC_PULSE - C_H_BACK_PORCH - R_char_h_cnt * 10;
                    // 得到当前字符 字模的 y 坐标
                    R_char_v_detail <=  R_v_cnt - C_V_SYNC_PULSE - C_V_BACK_PORCH - R_char_v_cnt * 20;

                    // 取字模
                    if(R_char_h_detail < 1 || R_char_h_detail >= 9 || R_char_v_detail < 2 || R_char_v_detail >= 18)
                        begin // 因为我们的像素是 10 * 20，而字模是 8 * 16，所以边缘不输出
                            O_red   <=  4'b0000   ;
                            O_green <=  4'b0000   ;
                            O_blue  <=  4'b0000   ; 
                        end  
                    else if(C_ascii_character[R_now_ascii][8 * (R_char_v_detail - 2) + R_char_h_detail - 1] == 1)
                        begin // 要输出的，全白，全 1
                            O_red   <=  4'b1111    ;
                            O_green <=  4'b1111    ;
                            O_blue  <=  4'b1111    ;
                        end
                    else
                        begin
                            O_red   <=  4'b0000   ;
                            O_green <=  4'b0000   ;
                            O_blue  <=  4'b0000   ; 
                        end  
                end
            else // 现在不能输出 RGB
                begin
                    O_red   <=  4'b0000    ;
                    O_green <=  4'b0000    ;
                    O_blue  <=  4'b0000    ; 
                end
        end
    end
endmodule







