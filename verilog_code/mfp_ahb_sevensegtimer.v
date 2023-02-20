`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/10/13 12:17:55
// Design Name: 
// Module Name: mfp_ahb_sevensegtimer
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


module mfp_ahb_sevensegtimer(
    input wire clk,
    input wire resetn,
    input wire [7:0] EN, // enable
    input wire [31:0] DIGITS, // each 7-seg <=> 4 DIGITS
    output reg [7:0] DISPENOUT, // 0111 1111 for 7seg 1
    output reg [7:0] DISPOUT // the corresponding 7seg decoding result
    );
        
        reg [7:0] decoding [15:0]; // the decoding table
        reg [2:0] choose; // which one to choose
        reg [3:0] value; // the value of the chosen one
        reg [15:0] counter; // counter to divide the frequence
        
        always @ (posedge clk or negedge resetn) begin
            
            // reset
            if(!resetn) begin
                DISPENOUT <= 8'hff; // everybody cannot be shown
                DISPOUT <= 8'h00; // all lights off
            end
            
            else begin
        
                // the decoding table
                decoding[4'h0] = 8'b111_1110_0;
                decoding[4'h1] = 8'b011_0000_0;
                decoding[4'h2] = 8'b110_1101_0;
                decoding[4'h3] = 8'b111_1100_0;
                decoding[4'h4] = 8'b011_0011_0;
                decoding[4'h5] = 8'b101_1011_0;
                decoding[4'h6] = 8'b101_1111_0;
                decoding[4'h7] = 8'b111_0000_0;
                decoding[4'h8] = 8'b111_1111_0;
                decoding[4'h9] = 8'b111_1011_0;
                decoding[4'ha] = 8'b111_0111_0;
                decoding[4'hb] = 8'b001_1111_0;
                decoding[4'hc] = 8'b000_1101_0;
                decoding[4'hd] = 8'b011_1101_0;
                decoding[4'he] = 8'b100_1111_0;
                decoding[4'hf] = 8'b100_0111_0;
                
                // decide which one to choose
                if (counter == 16'h8fff) begin
                    choose <= choose + 1;
                    counter <= 0;
                end
                else counter <= counter + 1;
                
                // choose the one to show
                DISPENOUT <= 8'hff; // init: everybody cannot be shown
                if (EN[choose] == 0) begin // check whether the chosen one is enabled
                    // if it's not
                    DISPOUT <= 8'h00; // all lights off
                end
                else begin // if it is enabled
                    DISPENOUT[choose] <= 0; // choose
                    case(choose) // 7seg decode
                        0: value <= DIGITS[3:0];
                        1: value <= DIGITS[7:4];
                        2: value <= DIGITS[11:8];
                        3: value <= DIGITS[15:12];
                        4: value <= DIGITS[19:16];
                        5: value <= DIGITS[23:20];
                        6: value <= DIGITS[27:24];
                        7: value <= DIGITS[31:28];
                    endcase
                    DISPOUT <= (~decoding[value]); // output the decoding value, 0 is lighting
                end
                
            end
        end

        
endmodule



















