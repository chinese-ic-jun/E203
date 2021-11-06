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
//  This module to implement the CSR instructions
//
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_alu_csrctrl(

  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The Handshake Interface 
  //
  input  csr_i_valid, // Handshake valid  //表示接收到了disp递交的信息
  output csr_i_ready, // Handshake ready  //表示处理完了disp递交的信息

  input  [`E203_XLEN-1:0] csr_i_rs1,
  input  [`E203_DECINFO_CSR_WIDTH-1:0] csr_i_info,
  input  csr_i_rdwen,   

  output csr_ena, //给csr读写使能信号
  output csr_wr_en,   //csr写使能信号
  output csr_rd_en,   //csr读使能信号
  output [12-1:0] csr_idx,  //csr寄存器的地址索引

  input  csr_access_ilgl,  //写回违例
  input  [`E203_XLEN-1:0] read_csr_dat, //读操作从csr寄存器中读出的数据
  output [`E203_XLEN-1:0] wbck_csr_dat, //写操作写入csr寄存器的数据

  
  `ifdef E203_HAS_CSR_NICE//{
  input          nice_xs_off,
  output         csr_sel_nice,
  output         nice_csr_valid,
  input          nice_csr_ready,
  output  [31:0] nice_csr_addr,
  output         nice_csr_wr,
  output  [31:0] nice_csr_wdata,
  input   [31:0] nice_csr_rdata,
  `endif//}


  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The CSR Write-back/Commit Interface  
  output csr_o_valid, // Handshake valid  //disp递交的信息需要发送到commit或在wbck处理
  input  csr_o_ready, // Handshake ready  //commit或者wbck处理完了
  //   The Write-Back Interface for Special (unaligned ldst and AMO instructions) 
  output [`E203_XLEN-1:0] csr_o_wbck_wdat,
  output csr_o_wbck_err,   

  input  clk,
  input  rst_n
  );


  `ifdef E203_HAS_CSR_NICE//{
      // If accessed the NICE CSR range then we need to check if the NICE CSR is ready
  assign csr_sel_nice        = (csr_idx[11:8] == 4'hE);
  wire sel_nice            = csr_sel_nice & (~nice_xs_off);
  wire addi_condi         = sel_nice ? nice_csr_ready : 1'b1; 

  assign csr_o_valid      = csr_i_valid
                            & addi_condi; // Need to make sure the nice_csr-ready is ready to make sure
                                          //  it can be sent to NICE and O interface same cycle
  assign nice_csr_valid    = sel_nice & csr_i_valid & 
                            csr_o_ready;// Need to make sure the o-ready is ready to make sure
                                        //  it can be sent to NICE and O interface same cycle

  assign csr_i_ready      = sel_nice ? (nice_csr_ready & csr_o_ready) : csr_o_ready; 

  assign csr_o_wbck_err   = csr_access_ilgl;
  assign csr_o_wbck_wdat  = sel_nice ? nice_csr_rdata : read_csr_dat;

  assign nice_csr_addr = csr_idx;
  assign nice_csr_wr   = csr_wr_en;
  assign nice_csr_wdata = wbck_csr_dat;
  `else//}{
  wire   sel_nice      = 1'b0;
  assign csr_o_valid      = csr_i_valid;
  assign csr_i_ready      = csr_o_ready;
  assign csr_o_wbck_err   = csr_access_ilgl;
  assign csr_o_wbck_wdat  = read_csr_dat;
  `endif//}


  wire        csrrw  = csr_i_info[`E203_DECINFO_CSR_CSRRW ];    //从infobus中读取相关信息
  wire        csrrs  = csr_i_info[`E203_DECINFO_CSR_CSRRS ];
  wire        csrrc  = csr_i_info[`E203_DECINFO_CSR_CSRRC ];
  wire        rs1imm = csr_i_info[`E203_DECINFO_CSR_RS1IMM];
  wire        rs1is0 = csr_i_info[`E203_DECINFO_CSR_RS1IS0];
  wire [4:0]  zimm   = csr_i_info[`E203_DECINFO_CSR_ZIMMM ];
  wire [11:0] csridx = csr_i_info[`E203_DECINFO_CSR_CSRIDX];

  wire [`E203_XLEN-1:0] csr_op1 = rs1imm ? {27'b0,zimm} : csr_i_rs1;  //生成操作数1

  assign csr_rd_en = csr_i_valid &          //生成读操作指示信号
    (
      (csrrw ? csr_i_rdwen : 1'b0) // the CSRRW only read when the destination reg need to be writen
      | csrrs | csrrc // The set and clear operation always need to read CSR
     );
  assign csr_wr_en = csr_i_valid & (        //生成写操作指示信号
                csrrw // CSRRW always write the original RS1 value into the CSR
               | ((csrrs | csrrc) & (~rs1is0)) // for CSRRS/RC, if the RS is x0, then should not really write                                        
            );                                                                           
                                                                                         
  assign csr_idx = csridx;      //生成访问csr寄存器的地址索引

  assign csr_ena = csr_o_valid & csr_o_ready & (~sel_nice); //生成csr寄存器读写使能信号

  assign wbck_csr_dat =     //生成写入csr寄存器的写入数据
              ({`E203_XLEN{csrrw}} & csr_op1)
            | ({`E203_XLEN{csrrs}} & (  csr_op1  | read_csr_dat))
            | ({`E203_XLEN{csrrc}} & ((~csr_op1) & read_csr_dat));

endmodule
