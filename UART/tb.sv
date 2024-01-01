class transaction;

	typedef enum bit {transmit = 0, receive=1} opert_type;
	randc opert_type operation;
//tx 
	rand bit [7:0] dintx;
	bit donetx;
	bit newd;
	bit tx;
// rx
	bit donerx;
	bit [7:0] doutrx;
	bit rx;

// copy constructor
	function transaction copy();
		copy = new();
		copy.operation = this.operation;
		copy.dintx = this.dintx;
		copy.newd  = this.newd;
		copy.tx = this.tx;
		copy.donerx = this.donerx;
		copy.doutrx =  this.doutrx;
		copy.rx = this.rx;
	endfunction
	
endclass
	
class generator;
		transaction tr;
		mailbox #(transaction) mbx;
		event donedr;
		event donescb;
		event done;
		bit [7:0] datax;
		function new(mailbox #(transaction) mbx);
			this.mbx = mbx;
			tr =new();
		endfunction
		
		task run();
          for (int i=0; i<10; i++)begin
				assert(tr.randomize) else $display("Randomization is failed");
				mbx.put(tr);
                $display("[GEN] : trasaction generated");
				@(donedr);
				@(donescb);
			end
			-> done;
		endtask
	endclass
	
class driver; 
		transaction tr;
		mailbox #(transaction) mbx;
		mailbox #(bit[7:0]) mbxds;
		event donedr;
		virtual uart_if vif;
  		bit [7:0] data;
  
        function new(mailbox #(transaction) mbx, mailbox #(bit [7:0]) mbxds);
			this.mbx = mbx;
			this.mbxds = mbxds;
		endfunction
		
		task reset();
			vif.rst <= 1'b1;
			vif.newd <= 1'b0;
			vif.dintx <=1'b0;
			vif.rx <= 1'b1;
			repeat (5)@(posedge vif.uclktx);
			$display("RESET is Done");
			$display("---------------------------------------");
			vif.rst <= 1'b0;
		endtask
		
		task run();
		forever begin
			mbx.get(tr);
          if (tr.operation ==0)begin
				@(posedge vif.uclktx);
				vif.newd <=1'b1;
				vif.dintx<= tr.dintx;
				@(posedge vif.uclktx);
				vif.newd <= 1'b0; 
                mbxds.put(tr.dintx);
                $display("[DRV]: Data Sent : %0d, Operation = Transmiter ", tr.dintx);
                wait(vif.donetx == 1'b1);  
                ->donedr;
			end
			
			else if (tr.operation == 1) begin
				@(posedge vif.uclkrx);
				  vif.rst <= 1'b0;
                  vif.rx <= 1'b0;
                  vif.newd <= 1'b0;
				@(posedge vif.uclkrx);
              for (int i=0; i<=7 ;i++)begin
					@(posedge vif.uclkrx);
					vif.rx <= $urandom;
					data[i] = vif.rx;
				end
				mbxds.put(data);
                $display("[DRV]: Data RCVD : %0d , Operation = RECEIVER", data);
				wait(vif.donerx==1'b1);
				vif.rx <= 1'b1;
				->donedr;
			end
		end
		endtask
		
	endclass
	
class monitor;
		bit [7:0] data;
		mailbox #(bit[7:0]) mbxms;
		virtual uart_if vif;
		
        function new(mailbox #(bit [7:0]) mbxms);
			this.mbxms = mbxms;
		endfunction
		
		task run();
			forever begin
				@(posedge vif.uclktx);
				if (vif.newd == 1'b1 && vif.rx==1'b1)begin //transmit mode
						@(posedge vif.uclktx);
						for(int i=0; i<=7; i++)begin
							@(posedge vif.uclktx);		
                            data[i] =vif.tx;
							
						end
						wait(vif.donetx==1);
                        repeat(1) @(posedge vif.uclktx);
                        $display("[MON]: Data Collected : %0d by Transmitter Operation ", data);
						mbxms.put(data);	
				end
				else if (vif.newd == 1'b0 && vif.rx==1'b0)begin // RX MODE
					wait(vif.donerx==1);
                     @(posedge vif.uclkrx);
					mbxms.put(vif.doutrx);
                    $display("[MON]: Data Collected : %0d by Receiver Operation ", vif.doutrx);
				end
			end
				
		endtask
	endclass
class scoreboard;
	bit [7:0] ref_data;
	bit [7:0] actual_data;
	mailbox #(bit [7:0]) mbxds;
	mailbox #(bit [7:0]) mbxms;
	event donescb;
       function new(mailbox #(bit [7:0]) mbxds, mailbox #(bit [7:0]) mbxms);
			this.mbxds = mbxds;
			this.mbxms = mbxms;
		endfunction
		
		task run();
			forever begin
				mbxds.get(ref_data);
				mbxms.get(actual_data);
				$display("[SCB] : DATA RCVD %0d",actual_data);
				if (actual_data == ref_data)begin
					$display("DATA MATCHED");
				end
				else begin
					$display("DATA MISMATCHED");
				end	
				$display("---------------------------------------");
				->donescb;
			end
		endtask
endclass

class environment;
	generator gen;
	driver drv;
	monitor mon;
	scoreboard scb;
	
	mailbox #(transaction) mbx;
	mailbox #(bit [7:0]) mbxds;
	mailbox #(bit [7:0]) mbxms;
	
	event nextdr;
	event nextscb;
	event done;
	virtual uart_if vif;
	
	function new(virtual uart_if vif);
		mbx =new();
		mbxds =new();
		mbxms =new();
		
		gen = new(mbx);
		drv = new(mbx, mbxds);
		mon = new(mbxms);
		scb = new(mbxds,mbxms);
		
		gen.donedr = nextdr;
		drv.donedr = nextdr;
		
		gen.donescb = nextscb;
		scb.donescb = nextscb;
		
		this.vif = vif;
		drv.vif = this.vif;
		mon.vif = this.vif;
		
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

	environment env;
	uart_if vif();
	
	// Design instance with default params
	uart_top DUT(vif.clk,vif.rst,vif.rx,vif.dintx,vif.newd,vif.tx,vif.doutrx,vif.donetx, vif.donerx);
	
	always #10 vif.clk = ~vif.clk;
	
	assign vif.uclktx = DUT.utx.uclk;
	assign vif.uclkrx = DUT.rtx.uclk;
	
	initial begin
		vif.clk = 1'b0;
		env =new(vif);
		env.run();
	end
	
	initial begin
		$dumpfile("dump.vcd");
		$dumpvars;
	end
	
	endmodule
	