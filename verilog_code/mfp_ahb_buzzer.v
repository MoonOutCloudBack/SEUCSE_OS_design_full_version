`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/10/13 12:14:17
// Design Name: 
// Module Name: mfp_ahb_buzzer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mfp_ahb_buzzer(
    input wire clk,
    input wire resetn,
    input wire [31:0] numMicros,
    output reg buzz
    );
        // do re mi
        parameter CNT_MAX = 25'd24_999_999;
        parameter DO = 18'd190839;
        parameter RE = 18'd170067;
        parameter MI = 18'd151514;
        parameter FA = 18'd143265;
        parameter SO = 18'd127550;
        parameter LA = 18'd113635;
        parameter XI = 18'd101213;
        
        // copying supplementary 1.23
    	reg [2:0] NS; // we use 8 state, mute + do re mi ... xi
        reg [17:0] freq_cnt;
        reg [17:0] freq_data;
		
        
        // state assignment
        // we use the last 3 bits of numMicros to represent zero do re mi ...
        always @ (posedge clk or negedge resetn) begin
        
            // reset
            if(!resetn) begin
                NS <= 0;
                buzz <= 0; // mute
                freq_cnt <= 0;
                freq_data <= CNT_MAX;
            end
            
            else begin
                // assign the output frequency (freq_data)
                NS <= numMicros[2:0]; // get the note
                case (NS)
                    3'o0: freq_data <= CNT_MAX; // mute
                    3'o1: freq_data <= DO; // do
                    3'o2: freq_data <= RE; // re
                    3'o3: freq_data <= MI; // mi
                    3'o4: freq_data <= FA; // fa
                    3'o5: freq_data <= SO; // so
                    3'o6: freq_data <= LA; // la
                    3'o7: freq_data <= XI; // xi
                default: freq_data <= CNT_MAX; // mute
                endcase
                
                // let's get do re mi!
                if (freq_cnt == freq_data) begin
                    buzz <= 1; // a pulse
                    freq_cnt <= 0; // counter go back to 0
                end
                else begin
                    freq_cnt <= freq_cnt+1; // count the time
                    buzz <= 0;
                end
            end
            
        end

        
endmodule

















