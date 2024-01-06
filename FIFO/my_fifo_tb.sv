
///////////////////////////////////////////////
class transaction;
bit rd,wr;
bit full,empty;
bit [7:0] data_in;
bit [7:0] data_out;
rand bit oper;

constraint ctrl {
		oper dist {1:/50 , 0:/50};
}

endclass

//////////////////////////////////////////////

class generator;
transaction tr;
mailbox #(transaction) mbx;
int count=0;
int i=0; 
event next;
event done;

function new(mailbox #(transaction) mbx);

	this.mbx=mbx;
	tr=new();
	endfunction
task run();
	repeat (count) begin
		assert (tr.randomize) else $display("Randomization is failed");
		mbx.put(tr);
		i++;
		$display("[GEN]: Operation : %0d , and iteration :%0d",tr.oper,i);
		@(next);
	end
	->done;
	endtask
endclass

//////////////////////////////////////////////////

class driver;
transaction td;
mailbox #(transaction) mbx;
virtual fifo_if itf;

function new(mailbox #(transaction) mbx);
	this.mbx=mbx;
endfunction

task reset();
		itf.rst <= 1'b1;
		itf.wr <= 1'b0;
		itf.rd <= 1'b0;
		itf.data_in <= 'b0;
		repeat (5) @(posedge itf.clk);
		itf.rst<= 1'b0;
    $display("[DRV] : DUT Reset Done");
    $display("------------------------------------------");
	endtask
task write();
		@(posedge itf.clk);
		itf.rst <=1'b0;
		itf.rd  <=1'b0;
		itf.wr  <=1'b1;
		itf.data_in <= $urandom_range(1,10);
		@(posedge itf.clk);
		itf.wr<=1'b0;
  $display("[DRV] : DATA WRITE  data : %0d", itf.data_in);
		@(posedge itf.clk);
	endtask
task read();
		@(posedge itf.clk);
		itf.rst <=1'b0;
		itf.rd  <=1'b1;
		@(posedge itf.clk);
		itf.rd<=1'b0;
		$display("[DRV] : DATA READ");
		@(posedge itf.clk);
	endtask
task write_till_full();
		for (int i=0;i<16;i++) begin
		@(posedge itf.clk);
		itf.rst <=1'b0;
		itf.rd  <=1'b0;
		itf.wr  <=1'b1;
		itf.data_in <= $urandom_range(1,200);
		@(posedge itf.clk);
		itf.wr<=1'b0;
          $display("[DRV] : DATA WRITE  data : %0d in FIFO full task", itf.data_in);
		@(posedge itf.clk);
		end
	endtask
	
	task read_till_empty();
	for (int i=0; i<16 ;i++)begin
		@(posedge itf.clk);
		itf.rst <=1'b0;
		itf.rd  <=1'b1;
		@(posedge itf.clk);
		itf.rd<=1'b0;
      $display("[DRV] : DATA READ FIFO empty task");
		@(posedge itf.clk);
		end
	endtask
	
	
task run();
	forever begin
		mbx.get(td);
      	write_till_full();
		read_till_empty();
		if (td.oper == 1)
			write();
		else
			read();

		end
	endtask
endclass
//////////////////////////////////////////////////////////	

class monitor;

virtual fifo_if itf;
transaction tm;
mailbox #(transaction) mbx;

function new(mailbox #(transaction) mbx);

	this.mbx = mbx;
	endfunction
task run();
	tm =new();
	forever begin
      repeat (2) @(posedge itf.clk);
	tm.rd  = itf.rd;
	tm.wr  = itf.wr;
	tm.full = itf.full;
	tm.empty = itf.empty;
	tm.data_in = itf.data_in;
      @(posedge itf.clk);
	tm.data_out = itf.data_out;
	mbx.put(tm);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tm.wr, tm.rd, tm.data_in, tm.data_out, tm.full, tm.empty);
	end
	endtask
endclass
//////////////////////////////////////
/////////////////////////////////////////////////////
 
class scoreboard;
  
  mailbox #(transaction) mbx;  // Mailbox for communication
  transaction tr;          // Transaction object for monitoring
  event next;
  bit [7:0] din[$];       // Array to store written data
  bit [7:0] temp;         // Temporary data storage
  int err = 0;            // Error count
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;     
  endfunction;
 
  task run();
    forever begin
      mbx.get(tr);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
      
      if (tr.wr == 1'b1) begin
        if (tr.full == 1'b0) begin
          din.push_front(tr.data_in);
          $display("[SCO] : DATA STORED IN QUEUE :%0d", tr.data_in);
        end
        else begin
          $display("[SCO] : FIFO is full");
        end
        $display("--------------------------------------"); 
      end
    
      if (tr.rd == 1'b1) begin
        if (tr.empty == 1'b0) begin  
          temp = din.pop_back();
          
          if (tr.data_out == temp)
            $display("[SCO] : DATA MATCH");
          else begin
            $error("[SCO] : DATA MISMATCH");
            err++;
          end
        end
        else begin
          $display("[SCO] : FIFO IS EMPTY");
        end
        
        $display("--------------------------------------"); 
      end
      
      -> next;
    end
  endtask
  
endclass
///////////////////////////////////////////////////////////////////

class environment;

generator gen;
driver drv;
monitor mon;
scoreboard scb;

mailbox #(transaction) gdmbx;
mailbox #(transaction) msmbx;

event nexttgs;
virtual fifo_if itf;
  
function new (virtual fifo_if itf);

gdmbx = new();
gen = new(gdmbx);
drv = new(gdmbx);

msmbx = new();
mon = new(msmbx);
scb = new(msmbx);
this.itf = itf;

  
  // driver interface connect
  drv.itf = this.itf;
  //monitor interace initialize
  mon.itf = this.itf;

gen.next=nexttgs;
scb.next=nexttgs;

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
    join_any  /////////
endtask

task post_test();
  wait (gen.done.triggered);
	$display("---------------------------------------------");
  $display("Error Count :%0d", scb.err);
    $display("---------------------------------------------");
    $finish();
	endtask
task run();
  pre_test();
  test();
  post_test();
endtask

endclass
////////////////////////////////////////////////////

module tb;

fifo_if itf();

initial begin
	itf.clk=0;
end	

always #10 itf.clk<=~itf.clk;


FIFO dut (.clk(itf.clk), .rst(itf.rst), .wr(itf.wr), .rd(itf.rd), .din(itf.data_in),.dout(itf.data_out),.empty(itf.empty),.full(itf.full));

  environment env;
    
  initial begin
    env = new(itf);
    env.gen.count = 50;
    env.run();
  end
    
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end


endmodule