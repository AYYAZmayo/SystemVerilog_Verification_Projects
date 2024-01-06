interface apb_if;
  
  logic presetn;
  logic pclk;
  logic psel;
  logic penable;
  logic pwrite;
  logic [31:0] paddr, pwdata;
  logic [31:0] prdata;
  logic pready, pslverr;  
  
  
endinterface

class transaction;
	typedef enum int {write =0, read = 1, random = 2, error=3} opr_type;
	randc opr_type operation;
	rand bit psel;
	rand bit penable;
	rand bit pwrite;
	rand bit [31:0] paddr, pwdata;
	bit [31:0] prdata;
	bit pready;
	bit pslverr;
	
	 constraint addr_c {
  paddr > 1; paddr < 32;////2 3 4
  }
  
  constraint data_c {
  pwdata > 1; pwdata < 5000; /// 2-9
  }
	function void display(input string tag);
		$display("[%0s] : op=%0s , paddr =%0d , pwdata =%0d, psel=%0d, penable =%0d, pwrite =%0d, prdata=%0d, pready=%0d, pslverr =%0d",tag,
					operation.name(), paddr, pwdata, psel, penable, pwrite, prdata, pready, pslverr);
	endfunction
	
	function transaction copy();
			copy=new();
			copy.operation =this.operation;
			copy.psel = this.psel;
			copy.penable = this.penable;
			copy.pwrite = this.pwrite;
			copy.paddr = this.paddr;
			copy.pwdata = this.pwdata;
			copy.prdata = this.prdata;
			copy.pslverr =this. pslverr;
	endfunction
	
	endclass
	
	class generator;
		transaction tr;
		mailbox #(transaction) mbxdr;
		
		event done;
		event nextdr;
		event nextscb;
		int count=0;
		
		function new(mailbox #(transaction) mbxdr);
			this.mbxdr = mbxdr;
			tr =new();
		endfunction
		
		task run();
			repeat (count) begin
				assert(tr.randomize()) else $display("Randomization is failed");
				mbxdr.put(tr.copy);
				tr.display("GEN");
				@(nextdr);
				@(nextscb);
			end
			
			->done;
		endtask
		
	endclass
	
	class driver;
		transaction tr;
		mailbox #(transaction) mbxdr;
		virtual apb_if vif;
		event nextdr;
		
		
		function new(mailbox #(transaction) mbxdr);
			this.mbxdr =mbxdr;
		endfunction
		
		
		task reset ();
			vif.presetn<=0;
			vif.psel <=0;
			vif.penable <=0;
			vif.pwrite <= 0;
			vif.paddr <=0;
			vif.pwdata <=0;
			repeat (5) @(posedge vif.pclk);
			vif.presetn <=1;
			repeat (5) @(posedge vif.pclk);
			$display("---------------------------------");
			$display("RESET is DONE");
			$display("---------------------------------");
		endtask
		
		task write();
			@(posedge vif.pclk);
			vif.psel<= 1'b1;
			vif.pwrite <=1'b1;
			vif.penable <=1'b0;
			vif.paddr <= tr.paddr;
			vif.pwdata <= tr.pwdata;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b1;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b0;
			vif.psel<= 1'b0;
			vif.pwrite <=1'b0;
			$display("[DRV] : DATA WRITE OP data :%0d and addr : %0d", tr.pwdata, tr.paddr);
		endtask
		
		task read();
			@(posedge vif.pclk);
			vif.psel<= 1'b1;
			vif.penable <=1'b0;
			vif.pwrite <=1'b0;
			//vif.pwdata <= tr.pwdata;
			vif.paddr <= tr.paddr;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b1;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b0;
			vif.psel<= 1'b0;
			vif.pwrite <=1'b0;
			$display("[DRV] : DATA READ OP addr : %0d", tr.paddr);
			
		endtask
		
		task random();
			@(posedge vif.pclk);
			vif.psel<= 1;
			vif.penable <=0;
			//random values
			vif.pwrite <=tr.pwrite;
			vif.paddr <= tr.paddr;
			vif.pwdata <= tr.pwdata;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b0;
			vif.psel<= 1'b0;
			vif.pwrite <=1'b0;
			$display("[DRV] : RANDOM OPERATION");
		endtask
		
		task error();
			@(posedge vif.pclk);
			vif.psel<= 1'b1;
			vif.penable <=1'b0;
			//SLAVE error generation condition
			vif.pwrite <=tr.pwrite;
			vif.paddr <= $urandom_range(33,100); // should be beyond the range 
			vif.pwdata <= tr.pwdata;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b1;
			repeat(1) @(posedge vif.pclk);
			vif.penable <=1'b0;
			vif.psel<= 1'b0;
			vif.pwrite <=1'b0;
			$display("[DRV] : SLV ERROR");
		endtask
		
		task run();
			forever begin
				mbxdr.get(tr);
				if (tr.operation == 0)begin
					write();
				end
				else if (tr.operation == 1)begin
					read();
				end
				else if (tr.operation == 2)begin
					random();
				end
				else if (tr.operation == 3)begin
					error();
				end
				->nextdr;
			end
		endtask
	endclass
	//////////////////////////////////////////////////////////
	class monitor;
		virtual apb_if vif;
		transaction tr;
		mailbox #(transaction) mbxms;
		
		function new(mailbox #(transaction) mbxms);
			this.mbxms=mbxms;
			tr =new();
		endfunction
		
		task run();
			forever begin
				@(posedge vif.pclk);
				// detect the starting condition of a transaction 
				if (vif.psel == 1 && vif.penable != 1)begin
					// write acess check
					@(posedge vif.pclk);
					if (vif.psel == 1 && vif.penable == 1 && vif.pwrite==1) 
					begin
						@(posedge vif.pclk);
						tr.pwrite = vif.pwrite;
						tr.paddr = vif.paddr;
						tr.pwdata =vif.pwdata;
						tr.pready =vif.pready;
						tr.pslverr = vif.pslverr;
						$display("[MON] : DATA WRITE data : %0d and addr : %0d write :%0b", vif.pwdata, vif.paddr, vif.pwrite);
                       //@(posedge vif.pclk);
					end
					// read acess check
					//@(posedge vif.pclk);
					else if (vif.psel == 1 && vif.penable == 1 && vif.pwrite==0)
					begin
						@(posedge vif.pclk);
						tr.pwrite = vif.pwrite;
						tr.paddr = vif.paddr;
						tr.pwdata =vif.pwdata;
						tr.prdata= vif.prdata;
						tr.pready =vif.pready;
						tr.pslverr = vif.pslverr;
						@(posedge vif.pclk);
						$display("[MON] : DATA READ data : %0d and addr : %0d write:%0b", vif.prdata,vif.paddr, vif.pwrite);
						//@(posedge vif.pclk);
					end
					mbxms.put(tr);
					@(posedge vif.pclk);
				end
			end
		endtask
	endclass
	/////////////////////////////////////////
	class scoreboard;
		transaction tr_mon;
		mailbox #(transaction) mbxms;
		
		bit [31:0]temp_wdata[31:0]='{default:0};
		bit [31:0]rdata;
		
		event nextscb;
		
		function new(mailbox #(transaction) mbxms);
			this.mbxms = mbxms;
		endfunction
		
		task run();
			forever begin
				mbxms.get(tr_mon);
				$display("[SCO] : DATA RCVD wdata:%0d rdata:%0d addr:%0d write:%0b", tr_mon.pwdata, tr_mon.prdata, tr_mon.paddr, tr_mon.pwrite);
				if (tr_mon.pwrite==1 && tr_mon.pslverr==0)
				begin
					temp_wdata[tr_mon.paddr] =tr_mon.pwdata;
					$display("[SCO] : DATA STORED DATA : %0d ADDR: %0d",tr_mon.pwdata, tr_mon.paddr);
				end
				
				else if (tr_mon.pwrite==0 && tr_mon.pslverr==0)
				begin
					rdata = temp_wdata[tr_mon.paddr];
                  if( tr_mon.prdata == rdata)begin
						$display("[SCO] : Data Matched"); 
                  		$display("---------------------------------");
                  end
					else begin
						$display("[SCO] : Data Mismatched"); 
                  		$display("---------------------------------");
                    end
				end
				
				else if (tr_mon.pslverr)
				begin
					$display("[SCO] : SLV ERROR DETECTED");
                  	$display("---------------------------------");
				end
				->nextscb;
			end
		endtask
	endclass
	/////////////////////////////////////////
	class environment;
		generator gen;
		driver drv;
		monitor mon;
		scoreboard scb;
		
		mailbox #(transaction) mbxdr;
		mailbox #(transaction) mbxms;
		
		event nextgd;
		event nextgs;
		
		virtual apb_if vif;
		
		function new (virtual apb_if vif);
			mbxdr =new();
			mbxms = new();
			
			gen =new(mbxdr);
			drv = new(mbxdr);
			
			mon =new(mbxms);
			scb =new(mbxms);
			
			this.vif =vif;
			drv.vif =this.vif;
			mon.vif =this.vif;
			
			gen.nextdr =nextgd;
			drv.nextdr =nextgd;
			
			gen.nextscb =nextgs;
			scb.nextscb =nextgs;
		endfunction
		
		task pre_test();
			drv.reset();
		endtask
		
		task test();
			fork
				gen.run();
				drv.run();
				mon.run();
				scb.run();
			join_any
		
		endtask
		
		task post_test();
			wait(gen.done.triggered);
			$finish();
		endtask
		
		task run();
			pre_test();
			test();
			post_test();
		endtask
	
	endclass
	
module tb_top;
	
	   apb_if vif();
 
		apb_ram dut (vif.presetn, vif.pclk, vif.psel, vif.penable, vif.pwrite, vif.paddr, vif.pwdata, vif.prdata, vif.pready,vif.pslverr);
   
    initial begin
      vif.pclk <= 0;
    end
    
    always #10 vif.pclk <= ~vif.pclk;
    
    environment env;
    
    
    
    initial begin
      env = new(vif);
      env.gen.count = 20;
      env.run();
    end
      
    
    initial begin
      $dumpfile("dump.vcd");
      $dumpvars;
    end
   
    
 endmodule
	
