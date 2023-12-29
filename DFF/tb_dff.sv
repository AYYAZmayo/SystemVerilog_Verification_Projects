
interface dff_itf;
	logic clk;
	logic rst;
	logic din;
	logic q;
endinterface

class transaction;
	rand bit din;
	bit q;
  
	function transaction copy();
		copy=new();
		copy.din = this.din;
		copy.q = this.q;
	endfunction
  
    constraint data{
   		 din dist {0:= 50, 1 := 50};
    }
  
	
endclass

class generator;
	transaction tr;
	mailbox #(transaction) mbx;
	mailbox #(transaction) mbx1;
	event done;
	event next_tr;
	event next_scb;
	
	function new(mailbox #(transaction) mbx,mailbox #(transaction) mbx1);
		this.mbx =mbx;
		this.mbx1 =mbx1;
		tr =new();
	endfunction
	
	task run();
      for (int i=0; i<20 ; i++)begin
			assert(tr.randomize) else $display("Randomization is failed");
          	$display("---------------------------------------------");
            mbx.put(tr.copy);
			mbx1.put(tr.copy);
            $display("[GEN] : Value of DIN = %0d sent",tr.din);
			@(next_scb);
			//@(next_tr);
		end
		->done;
	endtask
endclass
	
class driver;
  
	transaction tr;
	mailbox #(transaction) mbx;
	event next_tr;
	virtual dff_itf vif;
	
	function new(mailbox #(transaction) mbx);
		this.mbx =mbx;
	endfunction
	
	task reset();
		vif.rst <= 1'b1;
      	vif.din <= 1'b0;
		repeat (5) @(posedge vif.clk);
        $display("---------------------------------------------");
		$display("RESET IS DONE");
		@(posedge vif.clk);
		vif.rst=1'b0;
	endtask
	
	task run();
		forever begin
			mbx.get(tr);
            //repeat (2)@(posedge vif.clk);
			vif.din <= tr.din;
          $display("[DRV] : value of DIN = %0d Recieved ",tr.din);
            @(posedge vif.clk);
          
		   // ->next_tr;
		end
	endtask
endclass

class monitor;
	transaction tr;
	mailbox #(transaction) mbx;
	virtual dff_itf vif;
	
	function new (mailbox #(transaction) mbx);
		this.mbx = mbx;
		tr =new();
	endfunction
	
	task run();
		forever begin
			repeat (2)@(posedge vif.clk);
			tr.q = vif.q;
			tr.din = vif.din;
			mbx.put(tr.copy);
          $display("[MON] : Value of DIN = %0d and q = %0d ",vif.din,vif.q);
		end
	endtask
endclass 

class scoreboard;
	transaction tr;
	transaction tr_ref;
	bit temp;
	mailbox #(transaction) mbx; //from monitor
	mailbox #(transaction) mbx1; // from generator
	event next_scb;
	
	function new (mailbox #(transaction) mbx, mailbox #(transaction) mbx1);
		this.mbx =mbx;
		this.mbx1 =mbx1;
	endfunction
	
	task run();
		forever begin
			mbx.get(tr);
			mbx1.get(tr_ref);
            if (tr_ref.din == tr.q)begin
          		$display("[SCB] : DIN = %0d  , q = %0d ",tr_ref.din,tr.q);
                $display("DATA MATCHED");
         	end
            else begin
                $display("[SCB] : DIN = %0d  , q = %0d ",tr_ref.din,tr.q);
                $display("DATA MISMATCHED");
            end
			->next_scb;
		end
	endtask
endclass


class environment;
		
		generator gen;
		driver drv;
		monitor mon;
		scoreboard scb;
		
		mailbox #(transaction) gdmbx; // generator to driver
		mailbox #(transaction) msmbx; // monitor to scoreboard
		mailbox #(transaction) gsmbx; //generator to scoreboard
		
		virtual dff_itf vif;
		event next_tr;
		event next_scb;
		
		function new(virtual dff_itf vif);
			
			gsmbx =new();
			
			gdmbx =new();
			gen = new(gdmbx,gsmbx);
			drv = new(gdmbx);
			
			msmbx =new();
			mon = new(msmbx);
			scb = new(msmbx,gsmbx);
			
			this.vif = vif;
			drv.vif  = this.vif;
			mon.vif  = this.vif;
			
			gen.next_tr = next_tr;
			drv.next_tr = next_tr;
			
			gen.next_scb = next_scb;
			scb.next_scb = next_scb;
			
		endfunction
		
		task pre_test();
			drv.reset();
		endtask
		
		task test ;
		
			fork
				gen.run();
				drv.run();
                mon.run();
                scb.run();
			join_any
		
		endtask
		
		task post_test();
			wait(gen.done.triggered);
			$display("---------------------------------------------");
			$finish();
		endtask
		
		
		task run();
			pre_test();
			test();
			post_test();
		endtask
endclass
	
module tb_top;
	
    dff_itf vif();
	environment env;
	always #5 vif.clk <= ~vif.clk;
	
	dff DUT (vif.clk, vif.rst, vif.din, vif.q);
		
		
	initial begin
		vif.clk<=0;
		env=new(vif);
		env.run();
	end
	
	initial begin
		$dumpfile("dump.vcd");
		$dumpvars;
	end
	
endmodule 

