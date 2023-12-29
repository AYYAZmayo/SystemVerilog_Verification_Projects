module dff (input clk, input rst, input din, output reg q);
	always @(posedge clk)begin
		if(rst)
			q<=1'b0;
		else
			q<=din;
	end
	
endmodule
