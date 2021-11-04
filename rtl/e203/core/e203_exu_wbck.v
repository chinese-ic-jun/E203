 /*                                                                      
 Copyright 2018-2020 Nuclei System Technology, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  The Write-Back module to arbitrate the write-back request to regfile
//
// ====================================================================

`include "e203_defines.v"

module e203_exu_wbck(

  //////////////////////////////////////////////////////////////
  // The ALU Write-Back Interface
  input  alu_wbck_i_valid, // Handshake valid //alu向wbck发起读写反馈请求
  output alu_wbck_i_ready, // Handshake ready //wbck向alu返回读写反馈请求
  input  [`E203_XLEN-1:0] alu_wbck_i_wdat, // 从alu写回的数据值
  input  [`E203_RFIDX_WIDTH-1:0] alu_wbck_i_rdidx, // 写回的寄存器索引值
  // If ALU have error, it will not generate the wback_valid to wback module
      // so we dont need the alu_wbck_i_err here

  //////////////////////////////////////////////////////////////
  // The Longp Write-Back Interface
  input  longp_wbck_i_valid, // Handshake valid //longpwbck向wbck发起读写反馈请求
  output longp_wbck_i_ready, // Handshake ready //wbck向longpwbck返回读写反馈请求
  input  [`E203_FLEN-1:0] longp_wbck_i_wdat, // 从longpwbck写回的数据值
  input  [5-1:0] longp_wbck_i_flags, // 从longpwbck写回标志
  input  [`E203_RFIDX_WIDTH-1:0] longp_wbck_i_rdidx, // 从longpwbck写回的寄存器索引
  input  longp_wbck_i_rdfpu, // 从longpwbck写回到FPU的标志

  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface to Regfile
  output  rf_wbck_o_ena, // 写使能
  output  [`E203_XLEN-1:0] rf_wbck_o_wdat, // 写回的数据值
  output  [`E203_RFIDX_WIDTH-1:0] rf_wbck_o_rdidx,  // 写回的寄存器索引


  
  input  clk,
  input  rst_n
  );


  // The ALU instruction can write-back only when there is no any 
  //  long pipeline instruction writing-back
  //    * Since ALU is the 1 cycle instructions, it have lowest 
  //      priority in arbitration
  wire wbck_ready4alu = (~longp_wbck_i_valid); //表示没有接收到来自longpebck模块的握手信号
  wire wbck_sel_alu = alu_wbck_i_valid & wbck_ready4alu; //表示只接收到了alu模块的握手信号没有longpwbck的握手信号
  // The Long-pipe instruction can always write-back since it have high priority 
  wire wbck_ready4longp = 1'b1;  //表面长指令具有最高优先级总是可以写回
  wire wbck_sel_longp = longp_wbck_i_valid & wbck_ready4longp; //表示接收到了longpwbck模块的握手信号



  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface
  wire rf_wbck_o_ready = 1'b1; // Regfile is always ready to be write because it just has 1 w-port //表示rf的读使能总是打开

  wire wbck_i_ready;    //直接与rf_wbck_o_ready相接，总是1
  wire wbck_i_valid;    //应该是表示接收到了哪个握手信号
  wire [`E203_FLEN-1:0] wbck_i_wdat;    //待写入数据来自alu还是longpebck
  wire [5-1:0] wbck_i_flags;   //写回的标志
  wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;  //待写回寄存器的索引是来自alu还是longpwbck
  wire wbck_i_rdfpu;

  assign alu_wbck_i_ready   = wbck_ready4alu   & wbck_i_ready; //没有接收到longpwbck的握手信号，就反馈一个握手信号给alu，表示握手成功
  assign longp_wbck_i_ready = wbck_ready4longp & wbck_i_ready;  //总是1，总是握手成功，总是可以写回，优先级最高

  assign wbck_i_valid = wbck_sel_alu ? alu_wbck_i_valid : longp_wbck_i_valid; //应该是表示接收到了哪个握手信号
  `ifdef E203_FLEN_IS_32//{
  assign wbck_i_wdat  = wbck_sel_alu ? alu_wbck_i_wdat  : longp_wbck_i_wdat;  //待写入数据来自alu还是longpebck
  `else//}{
  assign wbck_i_wdat  = wbck_sel_alu ? {{`E203_FLEN-`E203_XLEN{1'b0}},alu_wbck_i_wdat}  : longp_wbck_i_wdat;
  `endif//}
  assign wbck_i_flags = wbck_sel_alu ? 5'b0  : longp_wbck_i_flags;    //写回的标志
  assign wbck_i_rdidx = wbck_sel_alu ? alu_wbck_i_rdidx : longp_wbck_i_rdidx;   //待写回寄存器的索引是来自alu还是longpwbck
  assign wbck_i_rdfpu = wbck_sel_alu ? 1'b0 : longp_wbck_i_rdfpu; //写回fpu的标志

  // If it have error or non-rdwen it will not be send to this module
  //   instead have been killed at EU level, so it is always need to 
  //   write back into regfile at here
  assign wbck_i_ready  = rf_wbck_o_ready;
  wire rf_wbck_o_valid = wbck_i_valid;

  wire wbck_o_ena   = rf_wbck_o_valid & rf_wbck_o_ready;  //只要接到了请求就打开写回的使能

  assign rf_wbck_o_ena   = wbck_o_ena & (~wbck_i_rdfpu); //写回的不是fpu且接收到了握手信号就打开使能
  assign rf_wbck_o_wdat  = wbck_i_wdat[`E203_XLEN-1:0]; //写回的数据，写道rf通用寄存器
  assign rf_wbck_o_rdidx = wbck_i_rdidx;  // 写回数据的索引


endmodule                                      
                                               
                                               
                                               
