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
//  This module to implement the regular ALU instructions
//
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_alu_rglr(

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The Handshake Interface 
  //
  input  alu_i_valid, // Handshake valid //和disp单元的握手信号
  output alu_i_ready, // Handshake ready  //给disp的握手反馈信号

  input  [`E203_XLEN-1:0] alu_i_rs1,   //原寄存器1的值 被alu处理后的值
  input  [`E203_XLEN-1:0] alu_i_rs2,   //原寄存器2的值 被alu处理后的值
  input  [`E203_XLEN-1:0] alu_i_imm,   //立即数 被alu处理后的值
  input  [`E203_PC_SIZE-1:0] alu_i_pc, //pc值 被alu处理后的值
  input  [`E203_DECINFO_ALU_WIDTH-1:0] alu_i_info, //信息总线，所有的指令信息都存在里面 被alu处理后的值

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The ALU Write-back/Commit Interface
  output alu_o_valid, // Handshake valid
  input  alu_o_ready, // Handshake ready
  //   The Write-Back Interface for Special (unaligned ldst and AMO instructions) 
  output [`E203_XLEN-1:0] alu_o_wbck_wdat,   //由dpath给出运算结果，输出操作数运算结果给wbck进行写回
  output alu_o_wbck_err,      //不知道什么意思？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？
  output alu_o_cmt_ecall,        //不知道什么意思？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？
  output alu_o_cmt_ebreak,        //不知道什么意思？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？
  output alu_o_cmt_wfi,        //不知道什么意思？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？？


  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // To share the ALU datapath
  // 
  // The operands and info to ALU
  output alu_req_alu_add ,    //产生指令类型到响应的单元作运算 发送给dpath
  output alu_req_alu_sub ,    // 发送给dpath
  output alu_req_alu_xor ,    // 发送给dpath
  output alu_req_alu_sll ,    // 发送给dpath
  output alu_req_alu_srl ,    // 发送给dpath
  output alu_req_alu_sra ,    // 发送给dpath
  output alu_req_alu_or  ,    // 发送给dpath
  output alu_req_alu_and ,    // 发送给dpath
  output alu_req_alu_slt ,    // 发送给dpath
  output alu_req_alu_sltu,    // 发送给dpath
  output alu_req_alu_lui ,    // 发送给dpath
  output [`E203_XLEN-1:0] alu_req_alu_op1,      //输出操作数一 发送给dpath
  output [`E203_XLEN-1:0] alu_req_alu_op2,      //输出操作数二 发送给dpath


  input  [`E203_XLEN-1:0] alu_req_alu_res,      //由dpath输入操作数运算结果，再发送给wbck进行写回

  input  clk,
  input  rst_n
  );

  wire op2imm  = alu_i_info [`E203_DECINFO_ALU_OP2IMM ];  //该指令的第二个操作数是否使用立即数
  wire op1pc   = alu_i_info [`E203_DECINFO_ALU_OP1PC  ];    //该指令的第一个操作数是否使用pc值

  assign alu_req_alu_op1  = op1pc  ? alu_i_pc  : alu_i_rs1; //发送操作数一
  assign alu_req_alu_op2  = op2imm ? alu_i_imm : alu_i_rs2; //发送操作数二

  wire nop    = alu_i_info [`E203_DECINFO_ALU_NOP ] ;
  wire ecall  = alu_i_info [`E203_DECINFO_ALU_ECAL ];
  wire ebreak = alu_i_info [`E203_DECINFO_ALU_EBRK ];
  wire wfi    = alu_i_info [`E203_DECINFO_ALU_WFI ];

     // The NOP is encoded as ADDI, so need to uncheck it
  assign alu_req_alu_add  = alu_i_info [`E203_DECINFO_ALU_ADD ] & (~nop);  //产生指令类型发送给共享的运算通路
  assign alu_req_alu_sub  = alu_i_info [`E203_DECINFO_ALU_SUB ];
  assign alu_req_alu_xor  = alu_i_info [`E203_DECINFO_ALU_XOR ];
  assign alu_req_alu_sll  = alu_i_info [`E203_DECINFO_ALU_SLL ];
  assign alu_req_alu_srl  = alu_i_info [`E203_DECINFO_ALU_SRL ];
  assign alu_req_alu_sra  = alu_i_info [`E203_DECINFO_ALU_SRA ];
  assign alu_req_alu_or   = alu_i_info [`E203_DECINFO_ALU_OR  ];
  assign alu_req_alu_and  = alu_i_info [`E203_DECINFO_ALU_AND ];
  assign alu_req_alu_slt  = alu_i_info [`E203_DECINFO_ALU_SLT ];
  assign alu_req_alu_sltu = alu_i_info [`E203_DECINFO_ALU_SLTU];
  assign alu_req_alu_lui  = alu_i_info [`E203_DECINFO_ALU_LUI ];

  assign alu_o_valid = alu_i_valid;
  assign alu_i_ready = alu_o_ready;
  assign alu_o_wbck_wdat = alu_req_alu_res;

  assign alu_o_cmt_ecall  = ecall;   
  assign alu_o_cmt_ebreak = ebreak;   
  assign alu_o_cmt_wfi = wfi;   
  
  // The exception or error result cannot write-back
  assign alu_o_wbck_err = alu_o_cmt_ecall | alu_o_cmt_ebreak | alu_o_cmt_wfi;

endmodule
