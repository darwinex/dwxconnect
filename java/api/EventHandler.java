package api;

import org.json.JSONObject;


/*EventHandler Interface

This interfance can be used to define what should happen when 
specific events happen, like new ticks or orders. 
An example implementation can be found in DWXExampleClient.java. 
*/

public interface EventHandler {
    
    public void start(Client dwx);
    
    public void onTick(Client dwx, String symbol, double bid, double ask);
    
    public void onBarData(Client dwx, String symbol, String timeFrame, String time, double open, double high, double low, double close, int tickVolume);
    
	public void onHistoricData(Client dwx, String symbol, String timeFrame, JSONObject data);
	
	public void onHistoricTrades(Client dwx);
	
	public void onMessage(Client dwx, JSONObject message);
    
    public void onOrderEvent(Client dwx);
    
}