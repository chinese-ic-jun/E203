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
//  The OITF (Oustanding Instructions Track FIFO) to hold all the non-ALU long
//  pipeline instruction's status and information
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_oitf (
  output dis_ready,  //oitf 非满，可以进行派遣，即可以允许指令递交oitf 发给disp模块的

  input  dis_ena, //派遣一个长指令的使能信号，需要写入oitf
  input  ret_ena, //读出一个长指令的使能信号，需要从oitf中弹出 从longpwbck发出的，应该是长指令执行完的标记

  output [`E203_ITAG_WIDTH-1:0] dis_ptr, // oitf fifo的写地址 发给disp
  output [`E203_ITAG_WIDTH-1:0] ret_ptr, // oitf fifo的读地址 发给longpwbck

  output [`E203_RFIDX_WIDTH-1:0] ret_rdidx, // 回写的指令的目的操作数rd的索引
  output ret_rdwen,  // 回写的指令是否有需要写入的目的操作数rd使能
  output ret_rdfpu,  // 回写的指令的目的操作数是否是浮点操作数使能信号
  output [`E203_PC_SIZE-1:0] ret_pc,  // 回写的指令的pc值

  input  disp_i_rs1en, // 派遣指令需要读取rs1操作数寄存器
  input  disp_i_rs2en, // 派遣指令需要读取rs2操作数寄存器
  input  disp_i_rs3en, // 派遣指令需要读取rs3操作数寄存器//只有浮点指令才会读取第三个操作数寄存器
  input  disp_i_rdwen,  // 派遣指令需要写回rd操作数寄存器
  input  disp_i_rs1fpu, // 派遣指令操作数需要读取第一个浮点通用寄存器组 总是0
  input  disp_i_rs2fpu, // 派遣指令操作数需要读取第2个浮点通用寄存器组 总是0
  input  disp_i_rs3fpu, // 派遣指令操作数需要读取第3个浮点通用寄存器组 总是0
  input  disp_i_rdfpu, // 派遣指令操作数需要写回浮点通用寄存器组 总是0
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs1idx, //派遣指令rs1操作数的索引
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs2idx, //派遣指令rs2操作数的索引
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs3idx, //派遣指令rs3操作数的索引 总是0，只有浮点计算才能用到
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rdidx, //派遣指令rd操作数的索引
  input  [`E203_PC_SIZE    -1:0] disp_i_pc,     //派遣指令的pc值

  output oitfrd_match_disprs1,  // 派遣指令rs1和任意一个oitf中的rd有冲突标记  发送给disp
  output oitfrd_match_disprs2,  // 派遣指令rs2和任意一个oitf中的rd有冲突标记  发送给disp
  output oitfrd_match_disprs3,  // 派遣指令rs3和任意一个oitf中的rd有冲突标记  发送给disp
  output oitfrd_match_disprd,  // 派遣指令rd和任意一个oitf中的rd有冲突标记  发送给disp

  output oitf_empty, // oitf fifo的空标记，如果oitf fifo为空，那么表示肯定不会存在冲突 发送给lsuagu，alu，disp，exp，litebpu
  input  clk,
  input  rst_n
);

  wire [`E203_OITF_DEPTH-1:0] vld_set;  //充当写入某一位的一个使能信号
  wire [`E203_OITF_DEPTH-1:0] vld_clr;  //充当读出某一位的一个使能信号
  wire [`E203_OITF_DEPTH-1:0] vld_ena;  //读写都使能
  wire [`E203_OITF_DEPTH-1:0] vld_nxt;  //只有写使能，没有读使能
  wire [`E203_OITF_DEPTH-1:0] vld_r;  //各表项中是否存放了有效指令    //只有写使能，没有读使能
  wire [`E203_OITF_DEPTH-1:0] rdwen_r;  //各表项中指令是否写回结果寄存器
  wire [`E203_OITF_DEPTH-1:0] rdfpu_r;  //各表项中写回结果寄存器是否属于浮点
  wire [`E203_RFIDX_WIDTH-1:0] rdidx_r[`E203_OITF_DEPTH-1:0]; //记录操作数的fifo
  // The PC here is to be used at wback stage to track out the
  //  PC of exception of long-pipe instruction
  wire [`E203_PC_SIZE-1:0] pc_r[`E203_OITF_DEPTH-1:0];  //记录pc值的fifo

  wire alc_ptr_ena = dis_ena; //派遣一个长指令的使能信号，需要写入oitf
  wire ret_ptr_ena = ret_ena; //读出一个长指令的使能信号，需要从oitf中弹出 从longpwbck发出的，应该是长指令执行完的标记

  wire oitf_full ; //oitf满了，说明有长指令正在执行
  
  wire [`E203_ITAG_WIDTH-1:0] alc_ptr_r;//这应该是写指针
  wire [`E203_ITAG_WIDTH-1:0] ret_ptr_r;//这应该是读指针

  generate
  if(`E203_OITF_DEPTH > 1) begin: depth_gt1//{
      wire alc_ptr_flg_r;     //这应该是写回绕标志
      wire alc_ptr_flg_nxt = ~alc_ptr_flg_r;  //应该是写回绕标志
      wire alc_ptr_flg_ena = (alc_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & alc_ptr_ena; //预留了空位 表明写指针饶了一圈
      
      sirv_gnrl_dfflr #(1) alc_ptr_flg_dfflrs(alc_ptr_flg_ena, alc_ptr_flg_nxt, alc_ptr_flg_r, clk, rst_n); //写绕回标志变号
      
      wire [`E203_ITAG_WIDTH-1:0] alc_ptr_nxt; //写下一个指针
      
      assign alc_ptr_nxt = alc_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (alc_ptr_r + 1'b1);  //如果满了指针变0，没满就加1
      
      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) alc_ptr_dfflrs(alc_ptr_ena, alc_ptr_nxt, alc_ptr_r, clk, rst_n);
      
      
      wire ret_ptr_flg_r;   //这应该是读回绕标志
      wire ret_ptr_flg_nxt = ~ret_ptr_flg_r;  //读回绕标志
      wire ret_ptr_flg_ena = (ret_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & ret_ptr_ena;  //使得最大读地址和写地址相等

      sirv_gnrl_dfflr #(1) ret_ptr_flg_dfflrs(ret_ptr_flg_ena, ret_ptr_flg_nxt, ret_ptr_flg_r, clk, rst_n);   //读绕回标志变号
      
      wire [`E203_ITAG_WIDTH-1:0] ret_ptr_nxt;  //读下一个指针
      
      assign ret_ptr_nxt = ret_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (ret_ptr_r + 1'b1);  //如果满了读地址变0，如果没满读地址加1

      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) ret_ptr_dfflrs(ret_ptr_ena, ret_ptr_nxt, ret_ptr_r, clk, rst_n);

      assign oitf_empty = (ret_ptr_r == alc_ptr_r) &   (ret_ptr_flg_r == alc_ptr_flg_r);  //判断为空
      assign oitf_full  = (ret_ptr_r == alc_ptr_r) & (~(ret_ptr_flg_r == alc_ptr_flg_r)); //判断为满
  end//}
  else begin: depth_eq1//}{
      assign alc_ptr_r =1'b0;
      assign ret_ptr_r =1'b0;
      assign oitf_empty = ~vld_r[0];
      assign oitf_full  = vld_r[0];
  end//}
  endgenerate//}

  assign ret_ptr = ret_ptr_r;
  assign dis_ptr = alc_ptr_r;

 //// 
 //// // If the OITF is not full, or it is under retiring, then it is ready to accept new dispatch
 //// assign dis_ready = (~oitf_full) | ret_ena;
 // To cut down the loop between ALU write-back valid --> oitf_ret_ena --> oitf_ready ---> dispatch_ready --- > alu_i_valid
 //   we exclude the ret_ena from the ready signal
 assign dis_ready = (~oitf_full);
  
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs1idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs2idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs3idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rdidx;

  genvar i;
  generate //{
      for (i=0; i<`E203_OITF_DEPTH; i=i+1) begin:oitf_entries//{
  
        assign vld_set[i] = alc_ptr_ena & (alc_ptr_r == i);  //充当写入某一位的一个使能信号
        assign vld_clr[i] = ret_ptr_ena & (ret_ptr_r == i);  //充当读出某一位的一个使能信号
        assign vld_ena[i] = vld_set[i] |   vld_clr[i];      //读或者写使能
        assign vld_nxt[i] = vld_set[i] | (~vld_clr[i]);     //只有写使能，没有读使能
  
        sirv_gnrl_dfflr #(1) vld_dfflrs(vld_ena[i], vld_nxt[i], vld_r[i], clk, rst_n); //某一位的空满标志
        //Payload only set, no need to clear
        sirv_gnrl_dffl #(`E203_RFIDX_WIDTH) rdidx_dfflrs(vld_set[i], disp_i_rdidx, rdidx_r[i], clk);
        sirv_gnrl_dffl #(`E203_PC_SIZE    ) pc_dfflrs   (vld_set[i], disp_i_pc   , pc_r[i]   , clk);
        sirv_gnrl_dffl #(1)                 rdwen_dfflrs(vld_set[i], disp_i_rdwen, rdwen_r[i], clk);
        sirv_gnrl_dffl #(1)                 rdfpu_dfflrs(vld_set[i], disp_i_rdfpu, rdfpu_r[i], clk);

        assign rd_match_rs1idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs1en & (rdfpu_r[i] == disp_i_rs1fpu) & (rdidx_r[i] == disp_i_rs1idx);//rs1索引和表项中任何一个值相等
        assign rd_match_rs2idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs2en & (rdfpu_r[i] == disp_i_rs2fpu) & (rdidx_r[i] == disp_i_rs2idx);//rs2索引和表项中任何一个值相等
        assign rd_match_rs3idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs3en & (rdfpu_r[i] == disp_i_rs3fpu) & (rdidx_r[i] == disp_i_rs3idx);//rs3索引和表项中任何一个值相等
        assign rd_match_rdidx [i] = vld_r[i] & rdwen_r[i] & disp_i_rdwen & (rdfpu_r[i] == disp_i_rdfpu ) & (rdidx_r[i] == disp_i_rdidx );//rd索引和表项中任何一个值相等
  
      end//}
  endgenerate//}

  assign oitfrd_match_disprs1 = |rd_match_rs1idx;
  assign oitfrd_match_disprs2 = |rd_match_rs2idx;
  assign oitfrd_match_disprs3 = |rd_match_rs3idx;
  assign oitfrd_match_disprd  = |rd_match_rdidx ;

  assign ret_rdidx = rdidx_r[ret_ptr];
  assign ret_pc    = pc_r [ret_ptr];
  assign ret_rdwen = rdwen_r[ret_ptr];
  assign ret_rdfpu = rdfpu_r[ret_ptr];

endmodule


