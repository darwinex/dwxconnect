import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Arrays;
import org.junit.Assert;
import org.junit.Test;
import org.junit.Before;

import api.Client;
import api.EventHandler;

import static api.Helpers.*;



/*

Tests to check that the DWX_Client is working correctly.  

Please don't run this on your live account. It will open and close positions!

The MT4/5 server must be initialized with MaximumOrders>=5 and MaximumLotSize>=0.02. 


compile and run:

javac -cp ".;../;../libs/*" DWXUnitTest.java
java -cp ".;../;../libs/*" org.junit.runner.JUnitCore DWXUnitTest


JSON jar from here:
https://github.com/junit-team/junit4/wiki/Download-and-Install

*/

public class DWXUnitTest {
	
	final static String MetaTraderDirPath = "C:/Users/asd/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/";
	final static String symbol = "EURUSD";
	final static int magicNumber = 0;
	final static int numOpenOrders = 5;
	final static double lots = 0.02;  // 0.02 so that we can also test partial closing. 
	final static double priceOffset = 0.01;
	String[] types = {"buy", "sell", "buylimit", "selllimit", "buystop", "sellstop"};
	Client dwx;
	
	
	/*Initializes DWX_Client and closes all open orders. 
	*/
	@Before
    public void setUp() {
		try {
			dwx = new Client(null, MetaTraderDirPath, 5, 10, false, false);
			sleep(1000);
		} catch (Exception e) { 
			e.printStackTrace();
			Assert.fail("Could not start client in setUp().");
		}
		// make sure there are no open orders when starting the test. 
        if (!closeAllOrders())
            Assert.fail("Could not close orders in setUp().");
    }
    
	
	/*Opens multiple orders. 

    As long as not enough orders are open, it will send new 
    open_order() commands. This is needed because of possible 
    requotes or other errors during opening of an order.
	*/
	boolean openMultipleOrders() {
		for (int i=0; i<numOpenOrders; i++) {
			dwx.openOrder(symbol, "buy", lots, 0, 0, 0, magicNumber, "", 0);
		}
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 10000) {
			sleep(1000);
			now = System.currentTimeMillis();
			if (dwx.openOrders.length() == numOpenOrders)
				return true;
			// in case there was a requote, try again:
			dwx.openOrder(symbol, "buy", lots, 0, 0, 0, magicNumber, "", 0);
		}
		return false;
	}
	
    
	/*Closes all open orders. 

    As long as there are open orers, it will send new 
    close_all_orders() commands. This is needed because of 
    possible requotes or other errors during closing of an 
    order. 
	*/
	boolean closeAllOrders() {
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 10000) {
			// sometimes it could fail if for example there is a requote. so just try again. 
			dwx.closeAllOrders();
			sleep(1000);
			now = System.currentTimeMillis();
			if (dwx.openOrders.length() == 0)
				return true;
		}
		return false;
	}
	
	
	/*Subscribes to the test symbol. 
	*/
	public void subcribeSymbols() {
		
		String[] symbols = new String[1];
		symbols[0] = symbol;
        dwx.subscribeSymbols(symbols);
		
		double bid = -1;
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			now = System.currentTimeMillis();
			try {
				JSONObject jo = (JSONObject)dwx.marketData.get(symbol);
				bid = (double)jo.get("bid");
				break;
			} catch (Exception e) {
			}
			sleep(100);
		}
		Assert.assertTrue(bid > 0);
	}
	
	
	/*Checks if there are open orders for each order type. 
	*/
	public boolean allTypesOpen() {
		ArrayList<String> typesOpen = new ArrayList<>();
		// print(dwx.openOrders);
		for (String ticket : dwx.openOrders.keySet()) {
			JSONObject jo = (JSONObject)dwx.openOrders.get(ticket);
			typesOpen.add((String)jo.get("type"));
		}
		return typesOpen.containsAll(Arrays.asList(types));
	}
	
	
	/*Tries to open an order for each type that is not already open. 
	*/
	public void openMissingTypes() {
		JSONObject jo = (JSONObject)dwx.marketData.get(symbol);
		double bid = (double)jo.get("bid");
		double[] prices = {0, 0, bid-priceOffset, bid+priceOffset, bid+priceOffset, bid-priceOffset};
		
		ArrayList<String> typesOpen = new ArrayList<>();
		for (String ticket : dwx.openOrders.keySet()) {
			jo = (JSONObject)dwx.openOrders.get(ticket);
			typesOpen.add((String)jo.get("type"));
		}
		
		for (int i=0; i<types.length; i++) {
			if (typesOpen.contains(types[i])) 
				continue;
            dwx.openOrder(symbol, types[i], lots, prices[i], 0, 0, magicNumber, "", 0);
		}
	}
	
	
	/*Opens at least one order for each possible order type.

    It calls openMissingTypes() until at least one order is open 
    for each possible order type.
	*/
	public boolean openOrders() {
		
		boolean ato = false;
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			openMissingTypes();
			sleep(1000);
			now = System.currentTimeMillis();
			ato = allTypesOpen();
			if (ato)
				break;
		}
		Assert.assertTrue(ato);
		return ato;
	}
	
	
	/*Modifies all open orders. 

    It will try to set the SL and TP for all open orders. 
	*/
	public boolean modifyOrders() {
		
		for (String ticket : dwx.openOrders.keySet()) {
			JSONObject jo = (JSONObject)dwx.openOrders.get(ticket);
			String type = (String)jo.get("type");
			double openPrice = (double)jo.get("open_price");
			double sl = openPrice - priceOffset;
            double tp = openPrice + priceOffset;
			if (type.contains("sell")) {
				sl = openPrice + priceOffset;
				tp = openPrice - priceOffset;
			}
			dwx.modifyOrder(Integer.parseInt(ticket), lots, 0, sl, tp, 0);
		}
		boolean allSet = false;
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			now = System.currentTimeMillis();
			allSet = true;
			for (String ticket : dwx.openOrders.keySet()) {
				JSONObject jo = (JSONObject)dwx.openOrders.get(ticket);
				double sl = (double)jo.get("SL");
				double tp = (double)jo.get("TP");
				if (sl <= 0 || tp <= 0) 
					allSet = false;
			}
			if (allSet) 
				break;
			sleep(100);
		}
		Assert.assertTrue(allSet);
		return allSet;
	}
	
	
	/*Tries to close an one order. 

    This could fail if the closing of an orders takes too long and 
    then two orders might be closed. 
	*/
	public void closeOrder() {
		
		if (dwx.openOrders.length() == 0)
			Assert.fail("There are no order to close in testCloseOrder().");
		
		int ticket = -1;
		for (String t : dwx.openOrders.keySet()) {
			ticket = Integer.parseInt(t);
			break;
		}
		
		int numOrdersBefore = dwx.openOrders.length();
		
		
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			dwx.closeOrder(ticket, 0);
			sleep(1000);
			now = System.currentTimeMillis();
			if (dwx.openOrders.length() == numOrdersBefore-1) 
				break;
		}
		Assert.assertEquals(dwx.openOrders.length(), numOrdersBefore-1);
	}
	
	
	/*Tries to partially close an order. 
	*/
	public void closeOrderPartial() {
		
		double closeLots = 0.01;
		
		if (dwx.openOrders.length() == 0)
			Assert.fail("There are no order to close in testCloseOrder().");
		
		int ticket = -1;
		double lotsBefore = -1;
		for (String t : dwx.openOrders.keySet()) {
			JSONObject jo = (JSONObject)dwx.openOrders.get(t);
			String type = (String)jo.get("type");
			if (type.equals("buy")) {
				ticket = Integer.parseInt(t);
				lotsBefore = (double)jo.get("lots");
				break;
			}
		}
		Assert.assertTrue(ticket >= 0);
		Assert.assertTrue(lotsBefore > 0);
		
		double lots = -1;
		
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			dwx.closeOrder(ticket, closeLots);
			sleep(2000);
			now = System.currentTimeMillis();
			// need to loop because the ticket will change after modification. 
			boolean found = false;
			for (String t : dwx.openOrders.keySet()) {
				JSONObject jo = (JSONObject)dwx.openOrders.get(t);
				lots = (double)jo.get("lots");
				if (Math.abs(lotsBefore - closeLots - lots) < 0.001) {
					found = true;
					break;
				}
			}
			if (found)
				break;
		}
		Assert.assertTrue(lots > 0);
		Assert.assertTrue(Math.abs(lotsBefore - closeLots - lots) < 0.001);
	}
	
	
	/*Tests subscribing to a symbol, opening, modifying, closing 
    and partial closing of orders. 

    Combined to one test function because these tests have to be 
    executed in the correct order. 
	*/
	@Test
	public void testOpenModifyCloseOrder() {
		
		if (!closeAllOrders()) 
            Assert.fail("Could not close orders in testOpenModifyCloseOrder().");
		
		subcribeSymbols();
		
		if (!openOrders()) 
			Assert.fail("openOrders() returned false.");
		
		
		if (!modifyOrders()) 
			Assert.fail("modifyOrders() returned false.");
		
		closeOrder();
		
		closeOrderPartial();
		
		if (!closeAllOrders())
            Assert.fail("Could not close orders after testOpenModifyCloseOrder().");
	}
	
	
	/*Tests to close all open orders. 

    First it will try to open multiple orders. 
	*/
	@Test
	public void testCloseAllOrders() {
		
		if (!openMultipleOrders())
			Assert.fail("Could not open all orders in testCloseAllOrders().");
		
		Assert.assertTrue(closeAllOrders());
	}
	
	
	/*Tests to close all orders with a given symbol. 

    First it will try to open multiple orders. 
	*/
	@Test
	public void testCloseOrdersBySymbol() {
		
		if (!openMultipleOrders())
			Assert.fail("Could not open all orders in testCloseOrdersBySymbol().");
		
		dwx.closeOrdersBySymbol(symbol);
		
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			sleep(1000);
			now = System.currentTimeMillis();
			if (dwx.openOrders.length() == 0) 
				break;
			dwx.closeOrdersBySymbol(symbol);
		}
		Assert.assertEquals(dwx.openOrders.length(), 0);
	}
	
	
	/*Tests to close all orders with a given magic number. 

    First it will try to open multiple orders. 
	*/
	@Test
	public void testCloseOrdersByMagic() {
		
		if (!openMultipleOrders())
			Assert.fail("Could not open all orders in closeOrdersByMagic().");
		
		dwx.closeOrdersByMagic(magicNumber);
		
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			sleep(1000);
			now = System.currentTimeMillis();
			if (dwx.openOrders.length() == 0) 
				break;
			dwx.closeOrdersByMagic(magicNumber);
		}
		Assert.assertEquals(dwx.openOrders.length(), 0);
	}
	
	
	/*Tests the subscribeSymbolsBarData() function. 
	*/
	@Test
	public void testSubscribeSymbolsBarData() {
		
		String timeFrame = "M1";
		
		String[][] symbols = new String[1][2];
		symbols[0][0] = symbol;
		symbols[0][0] = timeFrame;
		
		dwx.subscribeSymbolsBarData(symbols);
		
		JSONObject jo = new JSONObject();
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			sleep(100);
			now = System.currentTimeMillis();
			try {
				jo = (JSONObject)dwx.barData.get(symbol + "_" + timeFrame);
				// print(jo);
				if (jo.length() > 0)
					break;
			} catch (Exception e) {
			}
		}
		Assert.assertTrue(jo.length() > 0);
	}
	
	
	/*Tests the getHistoricData() function. 
	*/
	@Test
	public void testGetHistoricData() {
		
		String timeFrame = "D1";
		
		long end = System.currentTimeMillis()/1000;
		long start = end - 30*24*60*60;  // last 30 days
		dwx.getHistoricData(symbol, timeFrame, start, end);
		
		JSONObject jo = new JSONObject();
		long startTime = System.currentTimeMillis();
		long now = System.currentTimeMillis();
		while (now < startTime + 5000) {
			sleep(100);
			now = System.currentTimeMillis();
			try {
				jo = (JSONObject)dwx.historicData.get(symbol + "_" + timeFrame);
				// print(jo);
				if (jo.length() > 0)
					break;
			} catch (Exception e) {
			}
		}
		Assert.assertTrue(jo.length() > 0);
	}
}
