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
//  The IFU to implement entire instruction fetch unit.
//
// ====================================================================
`include "e203_defines.v"

module e203_ifu(
  output[`E203_PC_SIZE-1:0] inspect_pc,   //这是做完了预测计算之后的pc值，连到了gpioA
  output ifu_active,  //这个信号总是1，意味着ifu模块一直活动着
  input  itcm_nohold,  //由执行单元的控制状态寄存器csr给出的不hold数据的指示信号

  input  [`E203_PC_SIZE-1:0] pc_rtvec,  //应该是复位后的pc初始值
  `ifdef E203_HAS_ITCM //{
  input  ifu2itcm_holdup,  //itcm给出hold数据的指示信号
  //input  ifu2itcm_replay,

  // The ITCM address region indication signal
  input [`E203_ADDR_SIZE-1:0] itcm_region_indic,//ift2icb给出的，不知道干麼的

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // Bus Interface to ITCM, internal protocol called ICB (Internal Chip Bus)
  //    * Bus cmd channel
  output ifu2itcm_icb_cmd_valid, // Handshake valid //返回给itcm的握手信号
  input  ifu2itcm_icb_cmd_ready, // Handshake ready //由itcm返回的握手信号
            // Note: The data on rdata or wdata channel must be naturally
            //       aligned, this is in line with the AXI definition
  output [`E203_ITCM_ADDR_WIDTH-1:0]   ifu2itcm_icb_cmd_addr, // Bus transaction start addr //输出给itcm的取指令地址

  //    * Bus RSP channel
  input  ifu2itcm_icb_rsp_valid, // Response valid //由itcm返回的握手信号
  output ifu2itcm_icb_rsp_ready, // Response ready  //返回给itcm的握手信号
  input  ifu2itcm_icb_rsp_err,   // Response error  //由itcm返回的取指令异常提示信号
            // Note: the RSP rdata is inline with AXI definition
  input  [`E203_ITCM_DATA_WIDTH-1:0] ifu2itcm_icb_rsp_rdata, //从itcm读出的数据
  `endif//}

  `ifdef E203_HAS_MEM_ITF //{
  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // Bus Interface to System Memory, internal protocol called ICB (Internal Chip Bus)
  //    * Bus cmd channel
  output ifu2biu_icb_cmd_valid, // Handshake valid  //返回给外部存储器的握手信号
  input  ifu2biu_icb_cmd_ready, // Handshake ready  //由外部存储器返回的握手信号
            // Note: The data on rdata or wdata channel must be naturally
            //       aligned, this is in line with the AXI definition
  output [`E203_ADDR_SIZE-1:0]   ifu2biu_icb_cmd_addr, // Bus transaction start addr //输出给外部存储器的取指令地址

  //    * Bus RSP channel
  input  ifu2biu_icb_rsp_valid, // Response valid //由外部存储器返回的握手信号
  output ifu2biu_icb_rsp_ready, // Response ready //返回给外部存储器的握手信号
  input  ifu2biu_icb_rsp_err,   // Response error //外部存储器返回的取指令异常提示信号
            // Note: the RSP rdata is inline with AXI definition
  input  [`E203_SYSMEM_DATA_WIDTH-1:0] ifu2biu_icb_rsp_rdata,   //从外部存储器读出的数据

  //input  ifu2biu_replay,
  `endif//}

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The IR stage to EXU interface
  output [`E203_INSTR_SIZE-1:0] ifu_o_ir,// The instruction register //将取到的指令直接发送到执行单元的译码模块和alu模块
  output [`E203_PC_SIZE-1:0] ifu_o_pc,   // The PC register along with //将取到指令的pc值直接发送到执行单元的译码模块
  output ifu_o_pc_vld,                    //发送到执行单元的握手信号，后经执行单元到交付模块
  output ifu_o_misalgn,                  // The fetch misalign //取址非对齐异常标志
  output ifu_o_buserr,                   // The fetch bus error //取址存储器访问错误标志
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs1idx, //该指令原操作数1的寄存器索引
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs2idx,  //该指令原操作数2的寄存器索引
  output ifu_o_prdt_taken,               // The Bxx is predicted as taken //由分支预测模块给出的需要跳转标志
  output ifu_o_muldiv_b2b,       //暂时不知道
  output ifu_o_valid, // Handshake signals with EXU stage //返回给执行单元的握手信号
  input  ifu_o_ready, //执行单元返回的握手信号

  output  pipe_flush_ack, //发送流水线冲刷信号
  input   pipe_flush_req, //来自cmt模块的流水线冲刷请求
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op1,  //冲刷操作数1
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op2,   //冲刷操作数2
  `ifdef E203_TIMING_BOOST//}
  input   [`E203_PC_SIZE-1:0] pipe_flush_pc,  //冲刷pc值
  `endif//}

      
  // The halt request come from other commit stage
  //   If the ifu_halt_req is asserting, then IFU will stop fetching new 
  //     instructions and after the oustanding transactions are completed,
  //     asserting the ifu_halt_ack as the response.
  //   The IFU will resume fetching only after the ifu_halt_req is deasserted
  input  ifu_halt_req,  //由执行单元输入暂停请求信号
  output ifu_halt_ack,  //发送暂停请求信号到执行单元

  input  oitf_empty,    //数据相关性判断标志
  input  [`E203_XLEN-1:0] rf2ifu_x1,  //通用状态寄存器给出的值
  input  [`E203_XLEN-1:0] rf2ifu_rs1, //通用状态寄存器给出的值
  input  dec2ifu_rden,    //写指令需要写结果操作数到目的寄存器 由disp给出
  input  dec2ifu_rs1en,   //该指令需要读取原操作数1 由disp给出
  input  [`E203_RFIDX_WIDTH-1:0] dec2ifu_rdidx, //目的寄存器索引 由执行中decode给出
  input  dec2ifu_mulhsu,  //指令为 mulh或mulhsu或mulhu，这些乘法指令都把结果的高32位放到目的寄存器 //由执行模块的decode给出，送到ifetch计算是否是ifu_o_muldiv_b2b指令
  input  dec2ifu_div   ,  //指令为除法指令
  input  dec2ifu_rem   ,  //指令为取余数指令
  input  dec2ifu_divu  ,  //指令为无符号除法指令
  input  dec2ifu_remu  ,  //指令为无符号取余数指令

  input  clk,
  input  rst_n
  );

  
  wire ifu_req_valid; 
  wire ifu_req_ready; 
  wire [`E203_PC_SIZE-1:0]   ifu_req_pc; 
  wire ifu_req_seq;
  wire ifu_req_seq_rv32;
  wire [`E203_PC_SIZE-1:0] ifu_req_last_pc;
  wire ifu_rsp_valid; 
  wire ifu_rsp_ready; 
  wire ifu_rsp_err;   
  //wire ifu_rsp_replay;   
  wire [`E203_INSTR_SIZE-1:0] ifu_rsp_instr; 

  e203_ifu_ifetch u_e203_ifu_ifetch(
    .inspect_pc   (inspect_pc),
    .pc_rtvec      (pc_rtvec),  
    .ifu_req_valid (ifu_req_valid),
    .ifu_req_ready (ifu_req_ready),
    .ifu_req_pc    (ifu_req_pc   ),
    .ifu_req_seq     (ifu_req_seq     ),
    .ifu_req_seq_rv32(ifu_req_seq_rv32),
    .ifu_req_last_pc (ifu_req_last_pc ),
    .ifu_rsp_valid (ifu_rsp_valid),
    .ifu_rsp_ready (ifu_rsp_ready),
    .ifu_rsp_err   (ifu_rsp_err  ),
    //.ifu_rsp_replay(ifu_rsp_replay),
    .ifu_rsp_instr (ifu_rsp_instr),
    .ifu_o_ir      (ifu_o_ir     ),
    .ifu_o_pc      (ifu_o_pc     ),
    .ifu_o_pc_vld  (ifu_o_pc_vld ),
    .ifu_o_misalgn (ifu_o_misalgn),
    .ifu_o_buserr  (ifu_o_buserr ),
    .ifu_o_rs1idx  (ifu_o_rs1idx),
    .ifu_o_rs2idx  (ifu_o_rs2idx),
    .ifu_o_prdt_taken(ifu_o_prdt_taken),
    .ifu_o_muldiv_b2b(ifu_o_muldiv_b2b),
    .ifu_o_valid   (ifu_o_valid  ),
    .ifu_o_ready   (ifu_o_ready  ),
    .pipe_flush_ack     (pipe_flush_ack    ), 
    .pipe_flush_req     (pipe_flush_req    ),
    .pipe_flush_add_op1 (pipe_flush_add_op1),     
  `ifdef E203_TIMING_BOOST//}
    .pipe_flush_pc      (pipe_flush_pc),  
  `endif//}
    .pipe_flush_add_op2 (pipe_flush_add_op2), 
    .ifu_halt_req  (ifu_halt_req ),
    .ifu_halt_ack  (ifu_halt_ack ),

    .oitf_empty    (oitf_empty   ),
    .rf2ifu_x1     (rf2ifu_x1    ),
    .rf2ifu_rs1    (rf2ifu_rs1   ),
    .dec2ifu_rden  (dec2ifu_rden ),
    .dec2ifu_rs1en (dec2ifu_rs1en),
    .dec2ifu_rdidx (dec2ifu_rdidx),
    .dec2ifu_mulhsu(dec2ifu_mulhsu),
    .dec2ifu_div   (dec2ifu_div   ),
    .dec2ifu_rem   (dec2ifu_rem   ),
    .dec2ifu_divu  (dec2ifu_divu  ),
    .dec2ifu_remu  (dec2ifu_remu  ),

    .clk           (clk          ),
    .rst_n         (rst_n        ) 
  );



  e203_ifu_ift2icb u_e203_ifu_ift2icb (
    .ifu_req_valid (ifu_req_valid),
    .ifu_req_ready (ifu_req_ready),
    .ifu_req_pc    (ifu_req_pc   ),
    .ifu_req_seq     (ifu_req_seq     ),
    .ifu_req_seq_rv32(ifu_req_seq_rv32),
    .ifu_req_last_pc (ifu_req_last_pc ),
    .ifu_rsp_valid (ifu_rsp_valid),
    .ifu_rsp_ready (ifu_rsp_ready),
    .ifu_rsp_err   (ifu_rsp_err  ),
    //.ifu_rsp_replay(ifu_rsp_replay),
    .ifu_rsp_instr (ifu_rsp_instr),
    .itcm_nohold   (itcm_nohold),

  `ifdef E203_HAS_ITCM //{
    .itcm_region_indic (itcm_region_indic),
    .ifu2itcm_icb_cmd_valid(ifu2itcm_icb_cmd_valid),
    .ifu2itcm_icb_cmd_ready(ifu2itcm_icb_cmd_ready),
    .ifu2itcm_icb_cmd_addr (ifu2itcm_icb_cmd_addr ),
    .ifu2itcm_icb_rsp_valid(ifu2itcm_icb_rsp_valid),
    .ifu2itcm_icb_rsp_ready(ifu2itcm_icb_rsp_ready),
    .ifu2itcm_icb_rsp_err  (ifu2itcm_icb_rsp_err  ),
    .ifu2itcm_icb_rsp_rdata(ifu2itcm_icb_rsp_rdata),
  `endif//}


  `ifdef E203_HAS_MEM_ITF //{
    .ifu2biu_icb_cmd_valid(ifu2biu_icb_cmd_valid),
    .ifu2biu_icb_cmd_ready(ifu2biu_icb_cmd_ready),
    .ifu2biu_icb_cmd_addr (ifu2biu_icb_cmd_addr ),
    .ifu2biu_icb_rsp_valid(ifu2biu_icb_rsp_valid),
    .ifu2biu_icb_rsp_ready(ifu2biu_icb_rsp_ready),
    .ifu2biu_icb_rsp_err  (ifu2biu_icb_rsp_err  ),
    .ifu2biu_icb_rsp_rdata(ifu2biu_icb_rsp_rdata),
    //.ifu2biu_replay (ifu2biu_replay),
  `endif//}

  `ifdef E203_HAS_ITCM //{
    .ifu2itcm_holdup (ifu2itcm_holdup),
    //.ifu2itcm_replay (ifu2itcm_replay),
  `endif//}

    .clk           (clk          ),
    .rst_n         (rst_n        ) 
  );

  assign ifu_active = 1'b1;// Seems the IFU never rest at block level
  
endmodule

