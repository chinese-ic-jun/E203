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
// Designer   : Bob Hu
//
// Description:
//  The mini-decode module to decode the instruction in IFU 
//
// ====================================================================
`include "e203_defines.v"

module e203_ifu_minidec(
                //译码解析出指令的部分信息
  // The IR stage to Decoder
  input  [`E203_INSTR_SIZE-1:0] instr,  //要进行译码的指令，来自ift2icb模块
  
  ////////////////////////////////////////////////////////////// 以下都是译码的结果
  // The Decoded Info-Bus


  output dec_rs1en, //指令需要读rs1操作数 作为一个寄存器的使能信号控制rs1寄存器索引的输出
  output dec_rs2en, //指令需要读rs2操作数 作为一个寄存器的使能信号控制rs2寄存器索引的输出
  output [`E203_RFIDX_WIDTH-1:0] dec_rs1idx,  //rs1寄存器的索引 5bit  
  output [`E203_RFIDX_WIDTH-1:0] dec_rs2idx,  //rs2寄存器的索引 5bit

  output dec_mulhsu,  //指令是mulshu指令//弃用了
  output dec_mul   ,  //指令是乘法指令
  output dec_div   ,  //指令是除法指令
  output dec_rem   ,  //指令是取余指令
  output dec_divu  ,  //指令是无符号除法指令
  output dec_remu  ,  //指令是无符号取余指令

  output dec_rv32,  //指令是32位指令还是16位指令  发送给预测模块
  output dec_bjp, //指令是普通指令还是分支指令  发送给预测模块
  output dec_jal, //指令是无条件直接跳转指令  发送给预测模块
  output dec_jalr,  //指令是无条件间接跳转指令  发送给预测模块
  output dec_bxx, //指令是带条件直接跳转指令  发送给预测模块
  output [`E203_RFIDX_WIDTH-1:0] dec_jalr_rs1idx, //无条件间接跳转指令rs1的索引 5bit  发送给预测模块
  output [`E203_XLEN-1:0] dec_bjp_imm   //分支指令中的立即数 32bit  发送给预测模块

  );

  e203_exu_decode u_e203_exu_decode(

  .i_instr(instr),
  .i_pc(`E203_PC_SIZE'b0),
  .i_prdt_taken(1'b0), 
  .i_muldiv_b2b(1'b0), 

  .i_misalgn (1'b0),
  .i_buserr  (1'b0),

  .dbg_mode  (1'b0),

  .dec_misalgn(),
  .dec_buserr(),
  .dec_ilegl(),

  .dec_rs1x0(),
  .dec_rs2x0(),
  .dec_rs1en(dec_rs1en),
  .dec_rs2en(dec_rs2en),
  .dec_rdwen(),
  .dec_rs1idx(dec_rs1idx),
  .dec_rs2idx(dec_rs2idx),
  .dec_rdidx(),
  .dec_info(),  
  .dec_imm(),
  .dec_pc(),

`ifdef E203_HAS_NICE//{
  .dec_nice   (),
  .nice_xs_off(1'b0),
  .nice_cmt_off_ilgl_o(),
`endif//}

  .dec_mulhsu(dec_mulhsu),
  .dec_mul   (dec_mul   ),
  .dec_div   (dec_div   ),
  .dec_rem   (dec_rem   ),
  .dec_divu  (dec_divu  ),
  .dec_remu  (dec_remu  ),

  .dec_rv32(dec_rv32),
  .dec_bjp (dec_bjp ),
  .dec_jal (dec_jal ),
  .dec_jalr(dec_jalr),
  .dec_bxx (dec_bxx ),

  .dec_jalr_rs1idx(dec_jalr_rs1idx),
  .dec_bjp_imm    (dec_bjp_imm    )  
  );


endmodule
