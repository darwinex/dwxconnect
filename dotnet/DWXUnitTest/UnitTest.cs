using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Linq;
using System.Threading;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using DWXConnect;
using static DWXConnect.Helpers;

/*

Tests to check that the DWX_Client is working correctly.  

Please don't run this on your live account. It will open and close positions!

The MT4/5 server must be initialized with MaximumOrders>=5 and MaximumLotSize>=0.02. 


compile and run tests:
dotnet build
dotnet test

Or in Visual Studio: 
Test -> Run All Tests

*/

namespace UnitTest
{
    [TestClass]
    public class UnitTest
    {

        string MetaTraderDirPath = "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/";
        string symbol = "EURUSD";
        int magicNumber = 0;
        int numOpenOrders = 5;
        double lots = 0.02;  // 0.02 so that we can also test partial closing. 
        double priceOffset = 0.01;
		string[] types = { "buy", "sell", "buylimit", "selllimit", "buystop", "sellstop" };
        Client dwx;
		

		/*Initializes DWX_Client and closes all open orders. 
		*/
        [TestInitialize]
        public void TestInitialize()
        {
            dwx = new Client(null, MetaTraderDirPath, 5,
                             10, false, false);
            Thread.Sleep(1000);
            // make sure there are no open orders when starting the test. 
            if (!closeAllOrders())
                Assert.Fail("Could not close orders in setUp().");
        }
		

        /*Opens multiple orders. 

		As long as not enough orders are open, it will send new 
		open_order() commands. This is needed because of possible 
		requotes or other errors during opening of an order.
		*/
        bool openMultipleOrders()
        {
            for (int i = 0; i < numOpenOrders; i++)
            {
                dwx.openOrder(symbol, "buy", lots, 0, 0, 0, magicNumber, "", 0);
            }
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
				Thread.Sleep(1000);
                now = DateTime.UtcNow;
                if (dwx.openOrders.Count == numOpenOrders)
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
        bool closeAllOrders()
        {
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 10);
            while (now < endTime)
            {
				// sometimes it could fail if for example there is a requote. so just try again. 
                dwx.closeAllOrders();
                Thread.Sleep(1000);
                now = DateTime.UtcNow;
                if (dwx.openOrders.Count == 0)
                    return true;
            }
            return false;
        }

		
		/*Subscribes to the test symbol. 
		*/
        public void subcribeSymbols()
        {

            string[] symbols = new string[1];
            symbols[0] = symbol;
            dwx.subscribeSymbols(symbols);

            double bid = -1;
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                now = DateTime.UtcNow;
                try
                {
                    bid = (double)dwx.marketData[symbol]["bid"];
                    break;
                }
                catch 
                {
                }
                Thread.Sleep(100);
            }
            Assert.IsTrue(bid > 0);
        }
		
		
		/*Checks if there are open orders for each order type. 
		*/
		public bool allTypesOpen() 
		{
			List<string> typesOpen = new List<string>();
            foreach (var x in dwx.openOrders)
            {
                typesOpen.Add((string)dwx.openOrders[x.Key]["type"]);
            }
            return typesOpen.ToArray().All(value => types.Contains(value));
		}
	
	
		/*Tries to open an order for each type that is not already open. 
		*/
		public void openMissingTypes() {
			
			double bid = (double)dwx.marketData[symbol]["bid"];
            double[] prices = { 0, 0, bid - priceOffset, bid + priceOffset, bid + priceOffset, bid - priceOffset };
			
			List<string> typesOpen = new List<string>();
            foreach (var x in dwx.openOrders)
            {
                typesOpen.Add((string)dwx.openOrders[x.Key]["type"]);
            }

            for (int i = 0; i < types.Length; i++)
            {
				if (typesOpen.Contains(types[i]))
					continue;
                dwx.openOrder(symbol, types[i], lots, prices[i], 0, 0, magicNumber, "", 0);
            }
		}


		/*Opens at least one order for each possible order type.

		It calls openMissingTypes() until at least one order is open 
		for each possible order type.
		*/
        public bool openOrders()
        {

            bool ato = false;
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
				openMissingTypes();
                Thread.Sleep(1000);
				now = DateTime.UtcNow;
                ato = allTypesOpen();
				if (ato)
					break;
            }
            
            Assert.IsTrue(ato);
            return ato;
        }


		/*Modifies all open orders. 
		
		It will try to set the SL and TP for all open orders. 
		*/
        public bool modifyOrders()
        {

            foreach (var x in dwx.openOrders)
            {
                JObject jo = (JObject)dwx.openOrders[x.Key];
                String type = (String)jo["type"];
                double openPrice = (double)jo["open_price"];
                double sl = openPrice - priceOffset;
                double tp = openPrice + priceOffset;
                if (type.Contains("sell"))
                {
                    sl = openPrice + priceOffset;
                    tp = openPrice - priceOffset;
                }
                dwx.modifyOrder(Int32.Parse(x.Key), lots, 0, sl, tp, 0);
            }
            bool allSet = false;
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                now = DateTime.UtcNow;
                allSet = true;
                foreach (var x in dwx.openOrders)
                {
                    JObject jo = (JObject)dwx.openOrders[x.Key];
                    double sl = (double)jo["SL"];
                    double tp = (double)jo["TP"];
                    if (sl <= 0 || tp <= 0)
                        allSet = false;
                }
                if (allSet)
                    break;
                Thread.Sleep(100);
            }
            Assert.IsTrue(allSet);
            return allSet;
        }


		/*Tries to close an one order. 

		This could fail if the closing of an orders takes too long and 
		then two orders might be closed. 
		*/
        public void closeOrder()
        {
            if (dwx.openOrders.Count == 0)
                Assert.Fail("There are no order to close in closeOrder().");

            int ticket = -1;
            foreach (var x in dwx.openOrders)
            {
                ticket = Int32.Parse(x.Key);
                break;
            }

            int numOrdersBefore = dwx.openOrders.Count;

            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                dwx.closeOrder(ticket, 0);
                Thread.Sleep(1000);
                now = DateTime.UtcNow;
                if (dwx.openOrders.Count == numOrdersBefore - 1)
                    break;
            }
            Assert.AreEqual(dwx.openOrders.Count, numOrdersBefore - 1);
        }


		/*Tries to partially close an order. 
		*/
        public void closeOrderPartial()
        {

            double closeLots = 0.01;

            if (dwx.openOrders.Count == 0)
                Assert.Fail("There are no order to close in closeOrderPartial().");

            int ticket = -1;
            double lotsBefore = -1;
            foreach (var x in dwx.openOrders)
            {
                string type = (string)dwx.openOrders[x.Key]["type"];
                if (type.Equals("buy"))
                {
                    ticket = Int32.Parse(x.Key);
                    lotsBefore = (double)dwx.openOrders[x.Key]["lots"];
                    break;
                }
            }

            Assert.IsTrue(ticket >= 0);
            Assert.IsTrue(lotsBefore > 0);

            double lots = -1;

            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                dwx.closeOrder(ticket, closeLots);
                Thread.Sleep(2000);
                now = DateTime.UtcNow;
                // need to loop because the ticket will change after modification. 
                bool found = false;
                foreach (var x in dwx.openOrders) 
                {
                    lots = (double)dwx.openOrders[x.Key]["lots"];
                    if (Math.Abs(lotsBefore - closeLots - lots) < 0.001) 
                    {
                        found = true;
                        break;
                    }
                }
                if (found)
                    break;
            }
            Assert.IsTrue(lots > 0);
            Assert.IsTrue(Math.Abs(lotsBefore - closeLots - lots) < 0.001);
        }
		

        /*Tests subscribing to a symbol, opening, modifying, closing 
		and partial closing of orders. 

		Combined to one test function because these tests have to be 
		executed in the correct order. 
		*/
        [TestMethod]
        public void testOpenModifyCloseOrder()
        {

            if (!closeAllOrders())
                Assert.Fail("Could not close orders in testOpenModifyCloseOrder().");

            subcribeSymbols();

            if (!openOrders())
                Assert.Fail("openOrders() returned false.");


            if (!modifyOrders())
                Assert.Fail("modifyOrders() returned false.");

            closeOrder();

            closeOrderPartial();

            if (!closeAllOrders())
                Assert.Fail("Could not close orders after testOpenModifyCloseOrder().");
        }


		/*Tests to close all open orders. 

		First it will try to open multiple orders. 
		*/
        [TestMethod]
        public void testCloseAllOrders()
        {

            if (!openMultipleOrders())
                Assert.Fail("Could not open all orders in testCloseAllOrders().");

            Assert.IsTrue(closeAllOrders());
        }


		/*Tests to close all orders with a given symbol. 
		
		First it will try to open multiple orders. 
		*/
        [TestMethod]
        public void testCloseOrdersBySymbol()
        {

            if (!openMultipleOrders())
                Assert.Fail("Could not open all orders in testCloseOrdersBySymbol().");

            dwx.closeOrdersBySymbol(symbol);

            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                Thread.Sleep(1000);
                now = DateTime.UtcNow;
                if (dwx.openOrders.Count == 0)
                    break;
                dwx.closeOrdersBySymbol(symbol);
            }
            Assert.AreEqual(dwx.openOrders.Count, 0);
        }
		
		
		/*Tests to close all orders with a given magic number. 

		First it will try to open multiple orders. 
		*/
        [TestMethod]
        public void testCloseOrdersByMagic()
        {

            if (!openMultipleOrders())
                Assert.Fail("Could not open all orders in closeOrdersByMagic().");

            dwx.closeOrdersByMagic(magicNumber);

            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                Thread.Sleep(1000);
                now = DateTime.UtcNow;
                if (dwx.openOrders.Count == 0)
                    break;
                dwx.closeOrdersByMagic(magicNumber);
            }
            Assert.AreEqual(dwx.openOrders.Count, 0);
        }


        /*Tests the subscribeSymbolsBarData() function. 
	    */
        [TestMethod]
        public void testSubscribeSymbolsBarData()
        {

            String timeFrame = "M1";

            string[,] symbols = new string[,]{ { symbol, timeFrame } };
            

            dwx.subscribeSymbolsBarData(symbols);

            JObject jo = new JObject();
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                Thread.Sleep(100);
                now = DateTime.UtcNow;
                try
                {
                    jo = (JObject)dwx.barData[symbol + "_" + timeFrame];
                    // print(jo);
                    if (jo.Count > 0)
                        break;
                }
                catch
                {
                }
            }
            Assert.IsTrue(jo.Count > 0);
        }

        /*Tests the getHistoricData() function. 
		*/
        [TestMethod]
        public void testGetHistoricData()
        {

            string timeFrame = "D1";

            long end = DateTimeOffset.Now.ToUnixTimeSeconds();
            long start = end - 30 * 24 * 60 * 60;  // last 30 days
            dwx.getHistoricData(symbol, timeFrame, start, end);

            JObject jo = new JObject();
            DateTime now = DateTime.UtcNow;
            DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, 5);
            while (now < endTime)
            {
                Thread.Sleep(100);
                now = DateTime.UtcNow;
                try
                {
                    // print(symbol + "_" + timeFrame);
                    // print(dwx.historicData);
                    jo = (JObject)dwx.historicData[symbol + "_" + timeFrame];
                    // print(jo);
                    if (jo.Count > 0)
                        break;
                }
                catch
                {
                }
            }
            Assert.IsTrue(jo.Count > 0);
        }
    }
}
