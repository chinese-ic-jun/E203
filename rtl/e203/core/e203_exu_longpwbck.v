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
//  The Write-Back module to arbitrate the write-back request from all 
//  long pipe modules
//
// ====================================================================

`include "e203_defines.v"

module e203_exu_longpwbck(




  //////////////////////////////////////////////////////////////
  // The LSU Write-Back Interface
  input  lsu_wbck_i_valid, // Handshake valid //接收握手请求信号 接收lsu的写回信息
  output lsu_wbck_i_ready, // Handshake ready //发送握手反馈信号  
  input  [`E203_XLEN-1:0] lsu_wbck_i_wdat,  //写回的数据 来自lsu
  input  [`E203_ITAG_WIDTH -1:0] lsu_wbck_i_itag, //写回指令的itag 来自lsu
  input  lsu_wbck_i_err , // The error exception generated  //写回的异常错误提示 来自lsu
  input  lsu_cmt_i_buserr , //访存错误异常错误提示 来自lsu
  input  [`E203_ADDR_SIZE -1:0] lsu_cmt_i_badaddr,  //产生访存错误的地址 来自lsu
  input  lsu_cmt_i_ld,  //产生访存错误为load指令 来自lsu
  input  lsu_cmt_i_st,  //产生访存错误为store指令 来自lsu

  //////////////////////////////////////////////////////////////
  // The Long pipe instruction Wback interface to final wbck module
  output longp_wbck_o_valid, // Handshake valid //表明有长指令rd需要发送到wbck写回到通用寄存器
  input  longp_wbck_o_ready, // Handshake ready //表明长指令rd写完了给了longpwbck一个反馈
  output [`E203_FLEN-1:0] longp_wbck_o_wdat,  //写回的数据值，发送给wbck
  output [5-1:0] longp_wbck_o_flags,    //从longpwbck写回的标志 5‘b0
  output [`E203_RFIDX_WIDTH -1:0] longp_wbck_o_rdidx, // 从longpwbck写回的寄存器索引
  output longp_wbck_o_rdfpu, // 从longpwbck写回FPU的标志 //0
  //
  // The Long pipe instruction Exception interface to commit stage
  output  longp_excp_o_valid,   //表明有异常需要发给excp处理
  input   longp_excp_o_ready,   //表明excp处理完了异常并给了longpwbck一个反馈
  output  longp_excp_o_insterr, //0
  output  longp_excp_o_ld,
  output  longp_excp_o_st,
  output  longp_excp_o_buserr , // The load/store bus-error exception generated
  output [`E203_ADDR_SIZE-1:0] longp_excp_o_badaddr,
  output [`E203_PC_SIZE -1:0] longp_excp_o_pc,
  //
  //The itag of toppest entry of OITF
  input  oitf_empty,  
  input  [`E203_ITAG_WIDTH -1:0] oitf_ret_ptr,  //oitf读指针
  input  [`E203_RFIDX_WIDTH-1:0] oitf_ret_rdidx,  //oitf读取rd的索引
  input  [`E203_PC_SIZE-1:0] oitf_ret_pc, //读取的pc值
  input  oitf_ret_rdwen,     // 回写的指令需要写入的目的操作数rd使能
  input  oitf_ret_rdfpu,     // 回写的指令的目的操作数是否是浮点操作数使能信号 0
  output oitf_ret_ena,      //读出一个长指令的使能，表示oitf中的长指令已经执行了
  
  `ifdef E203_HAS_NICE//{
  input  nice_longp_wbck_i_valid ,  //nice向longpwbck发送的读写请求信号
  output nice_longp_wbck_i_ready ,  //longpwbck向nice返回的读写反馈信号
  input  [`E203_XLEN-1:0]  nice_longp_wbck_i_wdat ,
  input  [`E203_ITAG_WIDTH-1:0]  nice_longp_wbck_i_itag ,
  input  nice_longp_wbck_i_err,
  `endif//}

  input  clk,
  input  rst_n
  );


  // The Long-pipe instruction can write-back only when it's itag 
  //   is same as the itag of toppest entry of OITF
  wire wbck_ready4lsu = (lsu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);//只有当长指令的itag和oitf的读指针相同时才能写回
  wire wbck_sel_lsu = lsu_wbck_i_valid & wbck_ready4lsu; //能够写回的标志

  `ifdef E203_HAS_NICE//{
  wire wbck_ready4nice = (nice_longp_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
  wire wbck_sel_nice = nice_longp_wbck_i_valid & wbck_ready4nice; 
  `endif//}

  //assign longp_excp_o_ld   = wbck_sel_lsu & lsu_cmt_i_ld;
  //assign longp_excp_o_st   = wbck_sel_lsu & lsu_cmt_i_st;
  //assign longp_excp_o_buserr = wbck_sel_lsu & lsu_cmt_i_buserr;
  //assign longp_excp_o_badaddr = wbck_sel_lsu ? lsu_cmt_i_badaddr : `E203_ADDR_SIZE'b0;

  assign {                         //我觉得就是简单的把lsu发来的信息发送给excp
         longp_excp_o_insterr
        ,longp_excp_o_ld   
        ,longp_excp_o_st  
        ,longp_excp_o_buserr
        ,longp_excp_o_badaddr } = 
             ({`E203_ADDR_SIZE+4{wbck_sel_lsu}} & 
              {
                1'b0,
                lsu_cmt_i_ld,
                lsu_cmt_i_st,
                lsu_cmt_i_buserr,
                lsu_cmt_i_badaddr
              }) 
              ;

  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface
  wire wbck_i_ready;
  wire wbck_i_valid;//能写回，且握手成功
  wire [`E203_FLEN-1:0] wbck_i_wdat;  //计算后要写回的数据
  wire [5-1:0] wbck_i_flags;     //长指令写回的标志 5‘b0
  wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;  //长指令要写回的索引
  wire [`E203_PC_SIZE-1:0] wbck_i_pc;  //长指令要写回的pc
  wire wbck_i_rdwen; // 回写的指令需要写入的目的操作数rd使能
  wire wbck_i_rdfpu; // 回写的指令的目的操作数是否是浮点操作数使能信号
  wire wbck_i_err ;  //写回的异常错误提示

  assign lsu_wbck_i_ready = wbck_ready4lsu & wbck_i_ready;  //写回成功

  assign wbck_i_valid =   ({1{wbck_sel_lsu}} & lsu_wbck_i_valid)  //能写回，且握手成功
                        `ifdef E203_HAS_NICE//{
                        |  ({1{wbck_sel_nice}} & nice_longp_wbck_i_valid)
                        `endif//}
                         ;
  `ifdef E203_FLEN_IS_32 //{
  wire [`E203_FLEN-1:0] lsu_wbck_i_wdat_exd = lsu_wbck_i_wdat;  //计算后要写回的数据
  `else//}{
  wire [`E203_FLEN-1:0] lsu_wbck_i_wdat_exd = {{`E203_FLEN-`E203_XLEN{1'b0}},lsu_wbck_i_wdat};
  `endif//}
  `ifdef E203_HAS_NICE//{
  wire [`E203_FLEN-1:0] nice_wbck_i_wdat_exd = {{`E203_FLEN-`E203_XLEN{1'b0}},nice_longp_wbck_i_wdat};
  `endif//}
  
  assign wbck_i_wdat  = ({`E203_FLEN{wbck_sel_lsu}} & lsu_wbck_i_wdat_exd )  //计算后要写回的数据
                        `ifdef E203_HAS_NICE//{
                        | ({`E203_FLEN{wbck_sel_nice}} & nice_wbck_i_wdat_exd )
                        `endif//}
                         ;
  assign wbck_i_flags  = 5'b0  //长指令写回的标志
                         ;
  `ifdef E203_HAS_NICE//{
  wire nice_wbck_i_err = nice_longp_wbck_i_err;
  `endif//}

  assign wbck_i_err   = wbck_sel_lsu & lsu_wbck_i_err  //收到来自lsu的异常错误提示
                         ;
  assign wbck_i_pc    = oitf_ret_pc;  //长指令的pc值
  assign wbck_i_rdidx = oitf_ret_rdidx; //长指令要写回母的寄存器的索引
  assign wbck_i_rdwen = oitf_ret_rdwen; //使能
  assign wbck_i_rdfpu = oitf_ret_rdfpu; //写回到fpu的标志 0

  // If the instruction have no error and it have the rdwen, then it need to 
  //   write back into regfile, otherwise, it does not need to write regfile
  wire need_wbck = wbck_i_rdwen & (~wbck_i_err);  //只有没有异常错误的指令才需要能写回通用寄存器

  // If the long pipe instruction have error result, then it need to handshake
  //   with the commit module.
  wire need_excp = wbck_i_err  //有异常错误的指令需要和交付模块接口
                   `ifdef E203_HAS_NICE//{
                   & (~ (wbck_sel_nice & nice_wbck_i_err))   
                   `endif//}
                   ;

  assign wbck_i_ready =   //需要保证交付模块和最终写回仲裁模块同时能够接受
       (need_wbck ? longp_wbck_o_ready : 1'b1)
     & (need_excp ? longp_excp_o_ready : 1'b1);


  assign longp_wbck_o_valid = need_wbck & wbck_i_valid & (need_excp ? longp_excp_o_ready : 1'b1);  //发送给wbck写回请求
  assign longp_excp_o_valid = need_excp & wbck_i_valid & (need_wbck ? longp_wbck_o_ready : 1'b1);   //发送给excp处理异常

  assign longp_wbck_o_wdat  = wbck_i_wdat ; //计算后要写回的数据
  assign longp_wbck_o_flags = wbck_i_flags ;
  assign longp_wbck_o_rdfpu = wbck_i_rdfpu ; //0
  assign longp_wbck_o_rdidx = wbck_i_rdidx;

  assign longp_excp_o_pc    = wbck_i_pc; //该指令的pc

  assign oitf_ret_ena = wbck_i_valid & wbck_i_ready;//写回成功且没有异常错误便从oitf表项中去除

  `ifdef E203_HAS_NICE//{
  assign nice_longp_wbck_i_ready = wbck_ready4nice & wbck_i_ready;
  `endif//}

endmodule                                      
                                               
                                               
                                               
