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
//  The ifetch module to generate next PC and bus request
//
// ====================================================================
`include "e203_defines.v"

module e203_ifu_ifetch(
  output[`E203_PC_SIZE-1:0] inspect_pc,   //当前指令的pc


  input  [`E203_PC_SIZE-1:0] pc_rtvec,    //这应该是复位后的默认pc值 默认是32‘b00001000
  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // Fetch Interface to memory system, internal protocol
  //    * IFetch REQ channel
  output ifu_req_valid, // Handshake valid   //ifetch向ift2icb发送一个读写请求信号
  input  ifu_req_ready, // Handshake ready   //ift2icb向ifetch返回读写接受信号
            // Note: the req-addr can be unaligned with the length indicated
            //       by req_len signal.
            //       The targetd (ITCM, ICache or Sys-MEM) ctrl modules 
            //       will handle the unalign cases and split-and-merge works
  output [`E203_PC_SIZE-1:0] ifu_req_pc, // Fetch PC  //提供一个pc给ift2icb 这是做完了预测计算后的pc值 下一条指令的pc
  output ifu_req_seq, // This request is a sequential instruction fetch  //这是表示顺序取址的信号  
  output ifu_req_seq_rv32, // This request is incremented 32bits fetch //由译码给出的是32位还是16位指令的标志
  output [`E203_PC_SIZE-1:0] ifu_req_last_pc, // The last accessed     //应该是当前指令的pc值
                                           // PC address (i.e., pc_r)
  //    * IFetch RSP channel
  input  ifu_rsp_valid, // Response valid  //ift2icb向ifetch发送读写请求反馈信号
  output ifu_rsp_ready, // Response ready //ifetch向ift2icb返回读写反馈接受信号
  input  ifu_rsp_err,   // Response error //读或者写反馈的错误标志指令提示信号
            // Note: the RSP channel always return a valid instruction
            //   fetched from the fetching start PC address.
            //   The targetd (ITCM, ICache or Sys-MEM) ctrl modules 
            //   will handle the unalign cases and split-and-merge works
  //input  ifu_rsp_replay,
  input  [`E203_INSTR_SIZE-1:0] ifu_rsp_instr, // Response instruction //读反馈的数据，从ift2icb传来的指令

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The IR stage to EXU interface
  output [`E203_INSTR_SIZE-1:0] ifu_o_ir,// The instruction register  //由低16位和高16位拼成的指令 发送到指令寄存器
  output [`E203_PC_SIZE-1:0] ifu_o_pc,   // The PC register along with   //当前指令pc值寄存到pc寄存器的值
  output ifu_o_pc_vld,  //经过alu到commit再到excp模块
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs1idx,  //rs1寄存器索引
  output [`E203_RFIDX_WIDTH-1:0] ifu_o_rs2idx,  //rs2寄存器索引
  output ifu_o_prdt_taken,               // The Bxx is predicted as taken  //预测为需要跳转
  output ifu_o_misalgn,                  // The fetch misalign    //取址非对齐异常  //直接是0
  output ifu_o_buserr,                   // The fetch bus error     //取址存储器访问错误  就是取址的时候发送了个err信号进来
  output ifu_o_muldiv_b2b,               // The mul/div back2back case  //不知道是干麼的
  output ifu_o_valid, // Handshake signals with EXU stage   //ifetch发送到disp的读写请求信号
  input  ifu_o_ready,   //disp向ifetch返回的读写请求接受信号

  output  pipe_flush_ack,  //表示branchslv，excp和longpwbck发送的信号已经接收无误
  input   pipe_flush_req, //branchslv和excp向ifetch发送的读写请求信号
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op1,    //冲刷流水线送来的操作数1
  input   [`E203_PC_SIZE-1:0] pipe_flush_add_op2,   //冲刷流水线送来操作数2
  `ifdef E203_TIMING_BOOST//}
  input   [`E203_PC_SIZE-1:0] pipe_flush_pc,    //应该是冲刷流水线送来的pc值
  `endif//}

      
  // The halt request come from other commit stage
  //   If the ifu_halt_req is asserting, then IFU will stop fetching new 
  //     instructions and after the oustanding transactions are completed,
  //     asserting the ifu_halt_ack as the response.
  //   The IFU will resume fetching only after the ifu_halt_req is deasserted
  input  ifu_halt_req,  //excp向ifetch发送的读写请求反馈信号 
  output ifu_halt_ack,  //表示excp发送来的信号已经接收无误


  input  oitf_empty,//数据相关性判断标志
  input  [`E203_XLEN-1:0] rf2ifu_x1, //来自通用寄存器x1的值
  input  [`E203_XLEN-1:0] rf2ifu_rs1, //来自通用寄存器rs1的值
  input  dec2ifu_rs1en,//这是来自执行模块的decode给出的结果，该指令需要读取原操作数1
  input  dec2ifu_rden,   //这是来自执行模块的decode给出的结果，写指令需要写结果操作数到目的寄存器
  input  [`E203_RFIDX_WIDTH-1:0] dec2ifu_rdidx, //这是来自执行模块的decode给出的结果，目的寄存器索引
  input  dec2ifu_mulhsu,  //这是来自执行模块的decode给出的结果，指令为 mulh或mulhsu或mulhu，这些乘法指令都把结果的高32位放到目的寄存器
  input  dec2ifu_div   ,  //这是来自执行模块的decode给出的结果，指令为除法指令
  input  dec2ifu_rem   ,  //这是来自执行模块的decode给出的结果，指令为取余指令
  input  dec2ifu_divu  ,  //这是来自执行模块的decode给出的结果，指令为无符号除法指令
  input  dec2ifu_remu  ,  //这是来自执行模块的decode给出的结果，指令为无符号取余指令

  input  clk,
  input  rst_n
  );

  wire ifu_req_hsked  = (ifu_req_valid & ifu_req_ready) ;   //ifetch向ift2icb发送读写请求，表示在这个过程中有取址正在进行
  wire ifu_rsp_hsked  = (ifu_rsp_valid & ifu_rsp_ready) ;   //ift2icb向ifetch发送的读写请求，表示在这个过程中取址完成需要把指令信息写入流水线寄存器中
  wire ifu_ir_o_hsked = (ifu_o_valid & ifu_o_ready) ;    //表示在这个过程将流水线寄存器中的指令发送到disp并在alu执行完了回到disp给了ifetch一个反馈
  wire pipe_flush_hsked = pipe_flush_req & pipe_flush_ack;  //收到了branchslv，excp和longpwbck的流水线冲刷请求，表示在这个过程中要冲刷流水线

  
 // The rst_flag is the synced version of rst_n
 //    * rst_n is asserted 
 // The rst_flag will be clear when
 //    * rst_n is de-asserted 
  wire reset_flag_r;    //复位标志
  sirv_gnrl_dffrs #(1) reset_flag_dffrs (1'b0, reset_flag_r, clk, rst_n);
 //
 // The reset_req valid is set when 
 //    * Currently reset_flag is asserting
 // The reset_req valid is clear when 
 //    * Currently reset_req is asserting
 //    * Currently the flush can be accepted by IFU
  wire reset_req_r;
  wire reset_req_set = (~reset_req_r) & reset_flag_r;   //如果有复位标志是1且之前不是处于复位状态，那就要设置复位
  wire reset_req_clr = reset_req_r & ifu_req_hsked;     //如果之前是复位状态且与ift2icb读写请求成功那就要清除复位
  wire reset_req_ena = reset_req_set | reset_req_clr;    //设置复位和清除复位都能成为使能
  wire reset_req_nxt = reset_req_set | (~reset_req_clr); //1.如果之前是复位状态不论复位标志是什么最后都是非复位状态
                                                         //2.如果之前不是复位状态且复位表示0，那就保持非复位状态
                                                         //3.如果之前不是复位状态且复位标志是1，那就设置成复位状态

  sirv_gnrl_dfflr #(1) reset_req_dfflr (reset_req_ena, reset_req_nxt, reset_req_r, clk, rst_n);

  wire ifu_reset_req = reset_req_r;  //复位请求信号





  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The halt ack generation
  wire halt_ack_set;
  wire halt_ack_clr;
  wire halt_ack_ena;
  wire halt_ack_r;
  wire halt_ack_nxt;

     // The halt_ack will be set when
     //    * Currently halt_req is asserting
     //    * Currently halt_ack is not asserting
     //    * Currently the ifetch REQ channel is ready, means
     //        there is no oustanding transactions
  wire ifu_no_outs;  //没有取址正在进行，正在将取址信息写入流水线寄存器
  assign halt_ack_set = ifu_halt_req & (~halt_ack_r) & ifu_no_outs; //接收到了来自excp暂停请求，且之前不是暂停的状态，就需要设置暂停
     // The halt_ack_r valid is cleared when 
     //    * Currently halt_ack is asserting
     //    * Currently halt_req is de-asserting
  assign halt_ack_clr = halt_ack_r & (~ifu_halt_req);  //如果之前是暂停状态且没有发来暂停请求，那就要把暂停状态清除

  assign halt_ack_ena = halt_ack_set | halt_ack_clr;   //设置暂停和清除暂停都能成为使能
  assign halt_ack_nxt = halt_ack_set | (~halt_ack_clr);//1.如果之前是暂停状态且没有接收到暂停请求，那就把暂停状态清除改为非暂停状态
                                                       //2.如果之前是暂停状态且接收到了暂停请求，那就维持原来暂停的状态
                                                       //3.如果之前不是暂停状态且没有接收暂停请求，那就维持原来非暂停状态
                                                       //4.如果之前不是暂停状态且接收到暂停请求，那就设置成暂停状态
  sirv_gnrl_dfflr #(1) halt_ack_dfflr (halt_ack_ena, halt_ack_nxt, halt_ack_r, clk, rst_n);

  assign ifu_halt_ack = halt_ack_r;  //如果是1，表示正处于暂停状态


  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The flush ack signal generation
   //
   //   Ideally the flush is acked when the ifetch interface is ready
   //     or there is rsponse valid 
   //   But to cut the comb loop between EXU and IFU, we always accept
   //     the flush, when it is not really acknowledged, we use a 
   //     delayed flush indication to remember this flush
   //   Note: Even if there is a delayed flush pending there, we
   //     still can accept new flush request
   assign pipe_flush_ack = 1'b1;  //表示一直能接收流水线冲刷请求

   wire dly_flush_set;
   wire dly_flush_clr;
   wire dly_flush_ena;
   wire dly_flush_nxt;

      // The dly_flush will be set when
      //    * There is a flush requst is coming, but the ifu
      //        is not ready to accept new fetch request
   wire dly_flush_r; //处于流水线冲刷阶段
   assign dly_flush_set = pipe_flush_req & (~ifu_req_hsked);  //有冲刷请求且没有取址正在进行，那就要设置冲刷流水线
      // The dly_flush_r valid is cleared when 
      //    * The delayed flush is issued
   assign dly_flush_clr = dly_flush_r & ifu_req_hsked;   //已经处于冲刷状态且有新的取址正在进行就要清除流水线冲刷状态
   assign dly_flush_ena = dly_flush_set | dly_flush_clr; //设置和清除都能成为使能
   assign dly_flush_nxt = dly_flush_set | (~dly_flush_clr);

   sirv_gnrl_dfflr #(1) dly_flush_dfflr (dly_flush_ena, dly_flush_nxt, dly_flush_r, clk, rst_n);

   wire dly_pipe_flush_req = dly_flush_r;    //处于流水线冲刷阶段
   wire pipe_flush_req_real = pipe_flush_req | dly_pipe_flush_req;  //处于流水线冲刷阶段且有冲刷请求就要真正的冲刷流水线



  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The IR register to be used in EXU for decoding   //关于ir寄存器的都是猜测
  wire ir_valid_set; //处于指令需要写入流水线寄存器的状态
  wire ir_valid_clr; //表示disp递交了指令或者产生了流水线冲刷，需要把指令寄存器中的指令擦除
  wire ir_valid_ena; //寄存和擦除都可以打开使能
  wire ir_valid_r;   //有指令正在写入流水线寄存器
  wire ir_valid_nxt;

  wire ir_pc_vld_set; //上一个pc值已经被用来取址了
  wire ir_pc_vld_clr; //表示disp递交了指令或者产生了流水线冲刷，需要把指令寄存器中的指令擦除
  wire ir_pc_vld_ena;   //写入和清除都能做使能
  wire ir_pc_vld_r;     //表示有新的pc正在写入寄存器
  wire ir_pc_vld_nxt;


     // The ir valid is set when there is new instruction fetched *and* 
     //   no flush happening 
  wire ifu_rsp_need_replay;      //不知道干麼的，接了0
  wire pc_newpend_r;    //下一个pc需要取址的状态
  wire ifu_ir_i_ready;  //当前的pc已经被用来取址了，且已经取址完成了
  assign ir_valid_set  = ifu_rsp_hsked & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
  assign ir_pc_vld_set = pc_newpend_r & ifu_ir_i_ready & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
     // The ir valid is cleared when it is accepted by EXU stage *or*
     //   the flush happening 
  assign ir_valid_clr  = ifu_ir_o_hsked | (pipe_flush_hsked & ir_valid_r);
  assign ir_pc_vld_clr = ir_valid_clr;

  assign ir_valid_ena  = ir_valid_set  | ir_valid_clr;
  assign ir_valid_nxt  = ir_valid_set  | (~ir_valid_clr); 
  assign ir_pc_vld_ena = ir_pc_vld_set | ir_pc_vld_clr;  
  assign ir_pc_vld_nxt = ir_pc_vld_set | (~ir_pc_vld_clr);  //pc寄存器同理

  sirv_gnrl_dfflr #(1) ir_valid_dfflr (ir_valid_ena, ir_valid_nxt, ir_valid_r, clk, rst_n);
  sirv_gnrl_dfflr #(1) ir_pc_vld_dfflr (ir_pc_vld_ena, ir_pc_vld_nxt, ir_pc_vld_r, clk, rst_n);

     // IFU-IR loaded with the returned instruction from the IFetch RSP channel
  wire [`E203_INSTR_SIZE-1:0] ifu_ir_nxt = ifu_rsp_instr;  //接收到来自ift2icb的指令
     // IFU-PC loaded with the current PC
  wire                     ifu_err_nxt = ifu_rsp_err;    //接收到来自ift2icb的erro

     // IFU-IR and IFU-PC as the datapath register, only loaded and toggle when the valid reg is set
  wire ifu_err_r;
  sirv_gnrl_dfflr #(1) ifu_err_dfflr(ir_valid_set, ifu_err_nxt, ifu_err_r, clk, rst_n);
  wire prdt_taken;  
  wire ifu_prdt_taken_r;
  sirv_gnrl_dfflr #(1) ifu_prdt_taken_dfflr (ir_valid_set, prdt_taken, ifu_prdt_taken_r, clk, rst_n);
  wire ifu_muldiv_b2b_nxt;
  wire ifu_muldiv_b2b_r;
  sirv_gnrl_dfflr #(1) ir_muldiv_b2b_dfflr (ir_valid_set, ifu_muldiv_b2b_nxt, ifu_muldiv_b2b_r, clk, rst_n);
     //To save power the H-16bits only loaded when it is 32bits length instru 
  wire [`E203_INSTR_SIZE-1:0] ifu_ir_r;// The instruction register
  wire minidec_rv32;
  wire ir_hi_ena = ir_valid_set & minidec_rv32;  //把指令发送到指令寄存器中
  wire ir_lo_ena = ir_valid_set;
  sirv_gnrl_dfflr #(`E203_INSTR_SIZE/2) ifu_hi_ir_dfflr (ir_hi_ena, ifu_ir_nxt[31:16], ifu_ir_r[31:16], clk, rst_n);
  sirv_gnrl_dfflr #(`E203_INSTR_SIZE/2) ifu_lo_ir_dfflr (ir_lo_ena, ifu_ir_nxt[15: 0], ifu_ir_r[15: 0], clk, rst_n);

  wire minidec_rs1en;
  wire minidec_rs2en;
  wire [`E203_RFIDX_WIDTH-1:0] minidec_rs1idx;
  wire [`E203_RFIDX_WIDTH-1:0] minidec_rs2idx;

  `ifndef E203_HAS_FPU//}
  wire minidec_fpu        = 1'b0;
  wire minidec_fpu_rs1en  = 1'b0;
  wire minidec_fpu_rs2en  = 1'b0;
  wire minidec_fpu_rs3en  = 1'b0;
  wire minidec_fpu_rs1fpu = 1'b0;
  wire minidec_fpu_rs2fpu = 1'b0;
  wire minidec_fpu_rs3fpu = 1'b0;
  wire [`E203_RFIDX_WIDTH-1:0] minidec_fpu_rs1idx = `E203_RFIDX_WIDTH'b0;
  wire [`E203_RFIDX_WIDTH-1:0] minidec_fpu_rs2idx = `E203_RFIDX_WIDTH'b0;
  `endif//}

  wire [`E203_RFIDX_WIDTH-1:0] ir_rs1idx_r;
  wire [`E203_RFIDX_WIDTH-1:0] ir_rs2idx_r;
  wire bpu2rf_rs1_ena;
  //FPU: if it is FPU instruction. we still need to put it into the IR register, but we need to mask off the non-integer regfile index to save power
  wire ir_rs1idx_ena = (minidec_fpu & ir_valid_set & minidec_fpu_rs1en & (~minidec_fpu_rs1fpu)) | ((~minidec_fpu) & ir_valid_set & minidec_rs1en) | bpu2rf_rs1_ena;
  wire ir_rs2idx_ena = (minidec_fpu & ir_valid_set & minidec_fpu_rs2en & (~minidec_fpu_rs2fpu)) | ((~minidec_fpu) & ir_valid_set & minidec_rs2en);
  wire [`E203_RFIDX_WIDTH-1:0] ir_rs1idx_nxt = minidec_fpu ? minidec_fpu_rs1idx : minidec_rs1idx;
  wire [`E203_RFIDX_WIDTH-1:0] ir_rs2idx_nxt = minidec_fpu ? minidec_fpu_rs2idx : minidec_rs2idx;
  sirv_gnrl_dfflr #(`E203_RFIDX_WIDTH) ir_rs1idx_dfflr (ir_rs1idx_ena, ir_rs1idx_nxt, ir_rs1idx_r, clk, rst_n); //寄存rs1，rs2的索引
  sirv_gnrl_dfflr #(`E203_RFIDX_WIDTH) ir_rs2idx_dfflr (ir_rs2idx_ena, ir_rs2idx_nxt, ir_rs2idx_r, clk, rst_n);

  wire [`E203_PC_SIZE-1:0] pc_r;
  wire [`E203_PC_SIZE-1:0] ifu_pc_nxt = pc_r; //当前指令的pc值
  wire [`E203_PC_SIZE-1:0] ifu_pc_r;
  sirv_gnrl_dfflr #(`E203_PC_SIZE) ifu_pc_dfflr (ir_pc_vld_set, ifu_pc_nxt,  ifu_pc_r, clk, rst_n); //寄存pc值

  assign ifu_o_ir  = ifu_ir_r; //寄存后的指令
  assign ifu_o_pc  = ifu_pc_r; //寄存后的pc值
    // Instruction fetch misaligned exceptions are not possible on machines that support extensions
    // with 16-bit aligned instructions, such as the compressed instruction set extension, C.
  assign ifu_o_misalgn = 1'b0;// Never happen in RV32C configuration 
  assign ifu_o_buserr  = ifu_err_r;  //寄存后取址存储器访问错误 //直接连接
  assign ifu_o_rs1idx = ir_rs1idx_r;  //寄存后的rs1寄存器索引
  assign ifu_o_rs2idx = ir_rs2idx_r;   //寄存后rs2寄存器索引
  assign ifu_o_prdt_taken = ifu_prdt_taken_r;      //寄存后的预测为需要跳转
  assign ifu_o_muldiv_b2b = ifu_muldiv_b2b_r;      //寄存后的b2b指令

  assign ifu_o_valid  = ir_valid_r;  //有新的指令写入流水线寄存器
  assign ifu_o_pc_vld = ir_pc_vld_r;   //有新的pc写入流水线寄存器

  // The IFU-IR stage will be ready when it is empty or under-clearing
  assign ifu_ir_i_ready   = (~ir_valid_r) | ir_valid_clr; //流水线寄存器中没有指令了

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // JALR instruction dependency check
  wire ir_empty = ~ir_valid_r;  //表示流水线寄存器中是空的
  wire ir_rs1en = dec2ifu_rs1en; //需要读取rs1的使能
  wire ir_rden = dec2ifu_rden;   //需要写回结果到目的寄存器
  wire [`E203_RFIDX_WIDTH-1:0] ir_rdidx = dec2ifu_rdidx; //来自decode的目的寄存器索引
  wire [`E203_RFIDX_WIDTH-1:0] minidec_jalr_rs1idx; //来自litebpu的rs1索引
  wire jalr_rs1idx_cam_irrdidx = ir_rden & (minidec_jalr_rs1idx == ir_rdidx) & ir_valid_r; //存在数据冒险

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // MULDIV BACK2BACK Fusing
  // To detect the sequence of MULH[[S]U] rdh, rs1, rs2;    MUL rdl, rs1, rs2
  // To detect the sequence of     DIV[U] rdq, rs1, rs2; REM[U] rdr, rs1, rs2  
  wire minidec_mul ;
  wire minidec_div ;
  wire minidec_rem ;
  wire minidec_divu;
  wire minidec_remu;
  assign ifu_muldiv_b2b_nxt =    //根据以下判断出它是一条b2b指令
      (
          // For multiplicaiton, only the MUL instruction following
          //    MULH/MULHU/MULSU can be treated as back2back
          ( minidec_mul & dec2ifu_mulhsu)
          // For divider and reminder instructions, only the following cases
          //    can be treated as back2back
          //      * DIV--REM
          //      * REM--DIV
          //      * DIVU--REMU
          //      * REMU--DIVU
        | ( minidec_div  & dec2ifu_rem)
        | ( minidec_rem  & dec2ifu_div)
        | ( minidec_divu & dec2ifu_remu)
        | ( minidec_remu & dec2ifu_divu)
      )
      // The last rs1 and rs2 indexes are same as this instruction
      & (ir_rs1idx_r == ir_rs1idx_nxt)
      & (ir_rs2idx_r == ir_rs2idx_nxt)
      // The last rs1 and rs2 indexes are not same as last RD index
      & (~(ir_rs1idx_r == ir_rdidx))
      & (~(ir_rs2idx_r == ir_rdidx))
      ;

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // Next PC generation
  wire minidec_bjp;
  wire minidec_jal;
  wire minidec_jalr;
  wire minidec_bxx;
  wire [`E203_XLEN-1:0] minidec_bjp_imm;

  // The mini-decoder to check instruciton length and branch type 
  e203_ifu_minidec u_e203_ifu_minidec (
      .instr       (ifu_ir_nxt         ),

      .dec_rs1en   (minidec_rs1en      ),
      .dec_rs2en   (minidec_rs2en      ),
      .dec_rs1idx  (minidec_rs1idx     ),
      .dec_rs2idx  (minidec_rs2idx     ),

      .dec_rv32    (minidec_rv32       ),
      .dec_bjp     (minidec_bjp        ),
      .dec_jal     (minidec_jal        ),
      .dec_jalr    (minidec_jalr       ),
      .dec_bxx     (minidec_bxx        ),

      .dec_mulhsu  (),
      .dec_mul     (minidec_mul ),
      .dec_div     (minidec_div ),
      .dec_rem     (minidec_rem ),
      .dec_divu    (minidec_divu),
      .dec_remu    (minidec_remu),



      .dec_jalr_rs1idx (minidec_jalr_rs1idx),
      .dec_bjp_imm (minidec_bjp_imm    )

  );

  wire bpu_wait;
  wire [`E203_PC_SIZE-1:0] prdt_pc_add_op1;  
  wire [`E203_PC_SIZE-1:0] prdt_pc_add_op2;

  e203_ifu_litebpu u_e203_ifu_litebpu(

    .pc                       (pc_r),
                              
    .dec_jal                  (minidec_jal  ),
    .dec_jalr                 (minidec_jalr ),
    .dec_bxx                  (minidec_bxx  ),
    .dec_bjp_imm              (minidec_bjp_imm  ),
    .dec_jalr_rs1idx          (minidec_jalr_rs1idx  ),

    .dec_i_valid              (ifu_rsp_valid),
    .ir_valid_clr             (ir_valid_clr),
                
    .oitf_empty               (oitf_empty),
    .ir_empty                 (ir_empty  ),
    .ir_rs1en                 (ir_rs1en  ),

    .jalr_rs1idx_cam_irrdidx  (jalr_rs1idx_cam_irrdidx),
  
    .bpu_wait                 (bpu_wait       ),  
    .prdt_taken               (prdt_taken     ),  
    .prdt_pc_add_op1          (prdt_pc_add_op1),  
    .prdt_pc_add_op2          (prdt_pc_add_op2),

    .bpu2rf_rs1_ena           (bpu2rf_rs1_ena),
    .rf2bpu_x1                (rf2ifu_x1    ),
    .rf2bpu_rs1               (rf2ifu_rs1   ),

    .clk                      (clk  ) ,
    .rst_n                    (rst_n )                 
  );
  // If the instruciton is 32bits length, increament 4, otherwise 2
  wire [2:0] pc_incr_ofst = minidec_rv32 ? 3'd4 : 3'd2;  //偏移量，如果是32位就是4如果是16位就是2

  wire [`E203_PC_SIZE-1:0] pc_nxt_pre; //计算没有冲刷流水线时应该使用的pc值
  wire [`E203_PC_SIZE-1:0] pc_nxt;  //真实情况下的pc值

  wire bjp_req = minidec_bjp & prdt_taken;   //译码为跳转信号，预测需要跳转，那这就是一个跳转请求

  wire ifetch_replay_req;  //这个一直是0，不知道干麼的

  wire [`E203_PC_SIZE-1:0] pc_add_op1 = 
                            `ifndef E203_TIMING_BOOST//}
                               pipe_flush_req  ? pipe_flush_add_op1 :
                               dly_pipe_flush_req  ? pc_r :
                            `endif//}
                               ifetch_replay_req  ? pc_r :
                               bjp_req ? prdt_pc_add_op1    :
                               ifu_reset_req   ? pc_rtvec :
                                                 pc_r;

  wire [`E203_PC_SIZE-1:0] pc_add_op2 =  
                            `ifndef E203_TIMING_BOOST//}
                               pipe_flush_req  ? pipe_flush_add_op2 :
                               dly_pipe_flush_req  ? `E203_PC_SIZE'b0 :
                            `endif//}
                               ifetch_replay_req  ? `E203_PC_SIZE'b0 :
                               bjp_req ? prdt_pc_add_op2    :
                               ifu_reset_req   ? `E203_PC_SIZE'b0 :
                                                 pc_incr_ofst ;

  assign ifu_req_seq = (~pipe_flush_req_real) & (~ifu_reset_req) & (~ifetch_replay_req) & (~bjp_req); //没有冲刷流水线，复位，且又不是跳转信号，就表示要顺序取址
  assign ifu_req_seq_rv32 = minidec_rv32;
  assign ifu_req_last_pc = pc_r;

  assign pc_nxt_pre = pc_add_op1 + pc_add_op2;  //计算下一条指令的pc值
  `ifndef E203_TIMING_BOOST//}
  assign pc_nxt = {pc_nxt_pre[`E203_PC_SIZE-1:1],1'b0};
  `else//}{
  assign pc_nxt = 
               pipe_flush_req ? {pipe_flush_pc[`E203_PC_SIZE-1:1],1'b0} :
               dly_pipe_flush_req ? {pc_r[`E203_PC_SIZE-1:1],1'b0} :
               {pc_nxt_pre[`E203_PC_SIZE-1:1],1'b0};
  `endif//}

  // The Ifetch issue new ifetch request when
  //   * If it is a bjp insturction, and it does not need to wait, and it is not a replay-set cycle
  //   * and there is no halt_request
  wire ifu_new_req = (~bpu_wait) & (~ifu_halt_req) & (~reset_flag_r) & (~ifu_rsp_need_replay); //如果没有这些情况就会发出新的取址请求

  // The fetch request valid is triggering when
  //      * New ifetch request
  //      * or The flush-request is pending
  wire ifu_req_valid_pre = ifu_new_req | ifu_reset_req | pipe_flush_req_real | ifetch_replay_req; //新的取址请求被触发
  // The new request ready condition is:
  //   * No outstanding reqeusts
  //   * Or if there is outstanding, but it is reponse valid back
  wire out_flag_clr; //取址结束
  wire out_flag_r;   //表示有一个取址正在进行中
  wire new_req_condi = (~out_flag_r) | out_flag_clr;  //可以进行新的取址的条件
  assign ifu_no_outs   = (~out_flag_r) | ifu_rsp_valid;
        // Here we use the rsp_valid rather than the out_flag_clr (ifu_rsp_hsked) because
        //   as long as the rsp_valid is asserting then means last request have returned the
        //   response back, in WFI case, we cannot expect it to be handshaked (otherwise deadlock)

  assign ifu_req_valid = ifu_req_valid_pre & new_req_condi;  //握手成功且有新请求除法就会发送新的读写请求到ift2icb

  //wire ifu_rsp2ir_ready = (ifu_rsp_replay | pipe_flush_req_real) ? 1'b1 : (ifu_ir_i_ready & (~bpu_wait));
  wire ifu_rsp2ir_ready = (pipe_flush_req_real) ? 1'b1 : (ifu_ir_i_ready & ifu_req_ready & (~bpu_wait));

  // Response channel only ready when:
  //   * IR is ready to accept new instructions
  assign ifu_rsp_ready = ifu_rsp2ir_ready;     //对取回来的指令已经处理完成了

  // The PC will need to be updated when ifu req channel handshaked or a flush is incoming
  wire pc_ena = ifu_req_hsked | pipe_flush_hsked;  //当前pc的处理已经完成，要进行下一条pc的取址

  sirv_gnrl_dfflr #(`E203_PC_SIZE) pc_dfflr (pc_ena, pc_nxt, pc_r, clk, rst_n);


 assign inspect_pc = pc_r;//这是当前指令的pc值


  assign ifu_req_pc    = pc_nxt;//下一条指令的pc

     // The out_flag will be set if there is a new request handshaked
  wire out_flag_set = ifu_req_hsked; //正在取址
     // The out_flag will be cleared if there is a request response handshaked
  assign out_flag_clr = ifu_rsp_hsked; //取址结束
  wire out_flag_ena = out_flag_set | out_flag_clr; 
     // If meanwhile set and clear, then set preempt
  wire out_flag_nxt = out_flag_set | (~out_flag_clr);    

  sirv_gnrl_dfflr #(1) out_flag_dfflr (out_flag_ena, out_flag_nxt, out_flag_r, clk, rst_n);

       // The pc_newpend will be set if there is a new PC loaded
  wire pc_newpend_set = pc_ena; //当前pc取址已经完成，需要将pc和指令放入流水线寄存器
     // The pc_newpend will be cleared if have already loaded into the IR-PC stage
  wire pc_newpend_clr = ir_pc_vld_set; //上一个pc已经处理完了
  wire pc_newpend_ena = pc_newpend_set | pc_newpend_clr;
     // If meanwhile set and clear, then set preempt
  wire pc_newpend_nxt = pc_newpend_set | (~pc_newpend_clr);

  sirv_gnrl_dfflr #(1) pc_newpend_dfflr (pc_newpend_ena, pc_newpend_nxt, pc_newpend_r, clk, rst_n);


  assign ifu_rsp_need_replay = 1'b0;
  assign ifetch_replay_req = 1'b0;

  `ifndef FPGA_SOURCE//{
  `ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off

CHECK_IFU_REQ_VALID_NO_X:
  assert property (@(posedge clk) disable iff (~rst_n)
                     (ifu_req_valid !== 1'bx)
                  )
  else $fatal ("\n Error: Oops, detected X value for ifu_req_valid !!! This should never happen. \n");

//synopsys translate_on
`endif//}
`endif//}

endmodule

