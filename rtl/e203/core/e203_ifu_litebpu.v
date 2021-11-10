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
//  The Lite-BPU module to handle very simple branch predication at IFU
//
// ====================================================================
`include "e203_defines.v"

module e203_ifu_litebpu(
  // Current PC
  input  [`E203_PC_SIZE-1:0] pc,  //当前取到指令的pc值

  // The mini-decoded info 
  input  dec_jal, //来自minidecode，当前指令是无条件直接跳转
  input  dec_jalr,  //来自minidecode，当前指令是无条件间接跳转
  input  dec_bxx, //来自minidecode，当前指令是有条件直接跳转
  input  [`E203_XLEN-1:0] dec_bjp_imm,  //来自minidecode，分支指令的立即数
  input  [`E203_RFIDX_WIDTH-1:0] dec_jalr_rs1idx, //来自minidecode，无条件间接跳转指令rs1的索引

  // The IR index and OITF status to be used for checking dependency
  input  oitf_empty,    //直接来自执行模块的oitf，当它为1时，则说明oitf为空，则不存在数据冒险
  input  ir_empty,  //说明此时ir寄存中的指令无效，不会被执行，比如分支预测失败后分支指令还会在ir寄存器中保留一个周期，此时需要将ir_empty置1，说明这是个无效指令
  input  ir_rs1en,  //说明此时ir寄存器中的指令需要读取rs1操作数  //来自disp模块
  input  jalr_rs1idx_cam_irrdidx, //说明当前执行的指令存在RAW冒险
  
  // The add op to next-pc adder
  output bpu_wait,  //预测时发现存在依赖，需要等待依赖解除才能预测 存在数据相关性
  output prdt_taken,      //分支预测为跳转
  output [`E203_PC_SIZE-1:0] prdt_pc_add_op1,   //预测的PC的op1  pc=op1+op2
  output [`E203_PC_SIZE-1:0] prdt_pc_add_op2,   //预测的PC的op2

  input  dec_i_valid, //来自ift2icb模块的握手信号 接收到新的指令

  // The RS1 to read regfile
  output bpu2rf_rs1_ena,  //说明下个周期会读取regfile
  input  ir_valid_clr,  //下个周期中ir寄存器中的指令无效
  input  [`E203_XLEN-1:0] rf2bpu_x1,  //x1寄存器的值  这是从通用寄存器来的
  input  [`E203_XLEN-1:0] rf2bpu_rs1, //rs1寄存器的值 这是从通用寄存器来的

  input  clk,
  input  rst_n
  );


  // BPU of E201 utilize very simple static branch prediction logics
  //   * JAL: The target address of JAL is calculated based on current PC value
  //          and offset, and JAL is unconditionally always jump
  //   * JALR with rs1 == x0: The target address of JALR is calculated based on
  //          x0+offset, and JALR is unconditionally always jump
  //   * JALR with rs1 = x1: The x1 register value is directly wired from regfile
  //          when the x1 have no dependency with ongoing instructions by checking
  //          two conditions:
  //            ** (1) The OTIF in EXU must be empty 
  //            ** (2) The instruction in IR have no x1 as destination register
  //          * If there is dependency, then hold up IFU until the dependency is cleared
  //   * JALR with rs1 != x0 or x1: The target address of JALR need to be resolved
  //          at EXU stage, hence have to be forced halted, wait the EXU to be
  //          empty and then read the regfile to grab the value of xN.
  //          This will exert 1 cycle performance lost for JALR instruction
  //   * Bxxx: Conditional branch is always predicted as taken if it is backward
  //          jump, and not-taken if it is forward jump. The target address of JAL
  //          is calculated based on current PC value and offset

  // The JAL and JALR is always jump, bxxx backward is predicted as taken  
  assign prdt_taken   = (dec_jal | dec_jalr | (dec_bxx & dec_bjp_imm[`E203_XLEN-1]));  //minidecode译码出是其中一种跳转就预测为需要跳转
  
  // The JALR with rs1 == x1 have dependency or xN have dependency
  wire dec_jalr_rs1x0 = (dec_jalr_rs1idx == `E203_RFIDX_WIDTH'd0);   //rs1寄存器的索引是0，则rs1x0记为1
  wire dec_jalr_rs1x1 = (dec_jalr_rs1idx == `E203_RFIDX_WIDTH'd1);   //rs1寄存器的索引是1，则rs1x1记为1
  wire dec_jalr_rs1xn = (~dec_jalr_rs1x0) & (~dec_jalr_rs1x1);  //如果既不是x0也不是x1那就是xn

  wire jalr_rs1x1_dep = dec_i_valid & dec_jalr & dec_jalr_rs1x1 & ((~oitf_empty) | (jalr_rs1idx_cam_irrdidx)); //判断依赖
  wire jalr_rs1xn_dep = dec_i_valid & dec_jalr & dec_jalr_rs1xn & ((~oitf_empty) | (~ir_empty));  //判断依赖

                      // If only depend to IR stage (OITF is empty), then if IR is under clearing, or
                          // it does not use RS1 index, then we can also treat it as non-dependency
  wire jalr_rs1xn_dep_ir_clr = (jalr_rs1xn_dep & oitf_empty & (~ir_empty)) & (ir_valid_clr | (~ir_rs1en));
  wire rs1xn_rdrf_r;
  wire rs1xn_rdrf_set = (~rs1xn_rdrf_r) & dec_i_valid & dec_jalr & dec_jalr_rs1xn & ((~jalr_rs1xn_dep) | jalr_rs1xn_dep_ir_clr);
  wire rs1xn_rdrf_clr = rs1xn_rdrf_r;
  wire rs1xn_rdrf_ena = rs1xn_rdrf_set |   rs1xn_rdrf_clr;
  wire rs1xn_rdrf_nxt = rs1xn_rdrf_set | (~rs1xn_rdrf_clr);

  sirv_gnrl_dfflr #(1) rs1xn_rdrf_dfflrs(rs1xn_rdrf_ena, rs1xn_rdrf_nxt, rs1xn_rdrf_r, clk, rst_n);

  assign bpu2rf_rs1_ena = rs1xn_rdrf_set;

  assign bpu_wait = jalr_rs1x1_dep | jalr_rs1xn_dep | rs1xn_rdrf_set; //存在依赖就需要等

  assign prdt_pc_add_op1 = (dec_bxx | dec_jal) ? pc[`E203_PC_SIZE-1:0]
                         : (dec_jalr & dec_jalr_rs1x0) ? `E203_PC_SIZE'b0
                         : (dec_jalr & dec_jalr_rs1x1) ? rf2bpu_x1[`E203_PC_SIZE-1:0]
                         : rf2bpu_rs1[`E203_PC_SIZE-1:0];  

  assign prdt_pc_add_op2 = dec_bjp_imm[`E203_PC_SIZE-1:0];  

endmodule
