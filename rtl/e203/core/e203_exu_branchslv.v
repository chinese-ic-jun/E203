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
//  The Branch Resolve module to resolve the branch instructions
//
// ====================================================================
`include "e203_defines.v"


module e203_exu_branchslv(  //分支解析：1.接收来自alu分支运算的数据
                            //        2.计算是否需要进行流水线冲刷
                            //        3.发送流水线冲刷信号给ifetch
                            //        4.给csr使能改变中断的状态

  //   The BJP condition final result need to be resolved at ALU
  input  cmt_i_valid,  //接收到来自alu的握手请求
  output cmt_i_ready, // 发送给alu的握手反馈信号，只有当指令不是分支指令的时候才握手成功
  input  cmt_i_rv32,        //来自alu
  input  cmt_i_dret,// The dret instruction//来自alu
  input  cmt_i_mret,// The ret instruction//来自alu
  input  cmt_i_fencei,// The fencei instruction//来自alu
  input  cmt_i_bjp,  //来自alu
  input  cmt_i_bjp_prdt,// The predicted ture/false  //来自alu
  input  cmt_i_bjp_rslv,// The resolved ture/false//来自alu
  input  [`E203_PC_SIZE-1:0] cmt_i_pc,  //当前指令的pc值//来自alu
  input  [`E203_XLEN-1:0] cmt_i_imm,// The resolved ture/false //当前指令的立即数

  input  [`E203_PC_SIZE-1:0] csr_epc_r,  //来自csr不知道是干啥的？？？？
  input  [`E203_PC_SIZE-1:0] csr_dpc_r,   //来自csr 不知道是干啥的？？？？


  input  nonalu_excpirq_flush_req_raw,  //来自excp
  input  brchmis_flush_ack,   //冲刷完毕，能够接收新的冲刷请求
  output brchmis_flush_req,   //冲刷请求，发送给ifetch
  output [`E203_PC_SIZE-1:0] brchmis_flush_add_op1,  //应该是冲刷流水线后的操作数 发送给ifetch
  output [`E203_PC_SIZE-1:0] brchmis_flush_add_op2,  //应该是冲刷流水线后的操作数 发送给ifetch
  `ifdef E203_TIMING_BOOST//}
  output [`E203_PC_SIZE-1:0] brchmis_flush_pc,  //应该是冲刷流水线后的pc值 发送给ifetch
  `endif//}

  output  cmt_mret_ena, //发送给csr，
  output  cmt_dret_ena, //发送给excp，
  output  cmt_fencei_ena, //悬空了

  input  clk,
  input  rst_n
  );

  wire brchmis_flush_ack_pre;  //与ifetch握手成功
  wire brchmis_flush_req_pre;   //握手成功并产生流水线冲刷请求

  assign brchmis_flush_req = brchmis_flush_req_pre & (~nonalu_excpirq_flush_req_raw);  //需要进行冲刷且没有异常发生
  assign brchmis_flush_ack_pre = brchmis_flush_ack & (~nonalu_excpirq_flush_req_raw);  //冲刷完毕，能够接收新的冲刷请求
  // In Two stage impelmentation, several branch instructions are handled as below:
  //   * It is predicted at IFU, and target is handled in IFU. But 
  //             we need to check if it is predicted correctly or not. If not,
  //             we need to flush the pipeline
  //             Note: the JUMP instrution will always jump, hence they will be
  //                   both predicted and resolved as true
  wire brchmis_need_flush = (         //如果预测结果和真实结果不相符，则需要产生流水线冲刷
        (cmt_i_bjp & (cmt_i_bjp_prdt ^ cmt_i_bjp_rslv)) 
  //   If it is a FenceI instruction, it is always Flush 
       | cmt_i_fencei 
  //   If it is a RET instruction, it is always jump 
       | cmt_i_mret 
  //   If it is a DRET instruction, it is always jump 
       | cmt_i_dret 
      );

  wire cmt_i_is_branch = (                  //指令是分支指令
         cmt_i_bjp  
       | cmt_i_fencei 
       | cmt_i_mret 
       | cmt_i_dret 
      );

  assign brchmis_flush_req_pre = cmt_i_valid & brchmis_need_flush;  //alu发送来需要分支解析的数据且解析出需要进行冲刷，那就进行流水线冲刷

  // * If it is a DRET instruction, the new target PC is DPC register
  // * If it is a RET instruction, the new target PC is EPC register
  // * If predicted as taken, but actually it is not taken, then 
  //     The new target PC should caculated by PC+2/4
  // * If predicted as not taken, but actually it is taken, then 
  //     The new target PC should caculated by PC+offset
  assign brchmis_flush_add_op1 = cmt_i_dret ? csr_dpc_r : cmt_i_mret ? csr_epc_r : cmt_i_pc; 
  assign brchmis_flush_add_op2 = cmt_i_dret ? `E203_PC_SIZE'b0 : cmt_i_mret ? `E203_PC_SIZE'b0 :
                                 (cmt_i_fencei | cmt_i_bjp_prdt) ? (cmt_i_rv32 ? `E203_PC_SIZE'd4 : `E203_PC_SIZE'd2)
                                    : cmt_i_imm[`E203_PC_SIZE-1:0];
  `ifdef E203_TIMING_BOOST//}
      // Replicated two adders here to trade area with timing
  assign brchmis_flush_pc =               //如果是mret指令造成冲刷，则会使用mepc寄存器中的值作为重新取指令的pc
                                // The fenceI is also need to trigger the flush to its next instructions
                          (cmt_i_fencei | (cmt_i_bjp & cmt_i_bjp_prdt)) ? (cmt_i_pc + (cmt_i_rv32 ? `E203_PC_SIZE'd4 : `E203_PC_SIZE'd2)) :
                          (cmt_i_bjp & (~cmt_i_bjp_prdt)) ? (cmt_i_pc + cmt_i_imm[`E203_PC_SIZE-1:0]) :
                          cmt_i_dret ? csr_dpc_r :
                          //cmt_i_mret ? csr_epc_r :
                                       csr_epc_r ;// Last condition cmt_i_mret commented
                                                  //   to save gatecount and timing
  `endif//}

  wire brchmis_flush_hsked = brchmis_flush_req & brchmis_flush_ack; //有流水线冲刷正在进行
  assign cmt_mret_ena = cmt_i_mret & brchmis_flush_hsked; //造成了流水线冲刷，应该是要发给csr改变中断的状态
  assign cmt_dret_ena = cmt_i_dret & brchmis_flush_hsked; //造成了流水线冲刷，应该是要发给excp取读取dpc的值
  assign cmt_fencei_ena = cmt_i_fencei & brchmis_flush_hsked;

  assign cmt_i_ready = (~cmt_i_is_branch) | 
                             (
                                 (brchmis_need_flush ? brchmis_flush_ack_pre : 1'b1) 
                               // The Non-ALU flush will override the ALU flush
                                     & (~nonalu_excpirq_flush_req_raw) 
                             );

endmodule                                      
                                               
                                               
                                               
