using System;
using System.IO;
using System.Threading;
using System.Collections;
using Newtonsoft.Json.Linq;
using static DWXConnect.Helpers;


/*Client class

This class includes all of the functions for communication with MT4/MT5. 

*/

namespace DWXConnect
{
    public class Client
    {

        private EventHandler eventHandler;
        private string MetaTraderDirPath;  // { get; private set; }
        private int sleepDelay;
        private int maxRetryCommandSeconds;
        private bool loadOrdersFromFile;
        private bool verbose;

        private string pathOrders;
        private string pathMessages;
        private string pathMarketData;
        private string pathBarData;
        private string pathHistoricData;
        private string pathHistoricTrades;
        private string pathOrdersStored;
        private string pathMessagesStored;
        private string pathCommandsPrefix;

        private int maxCommandFiles = 20;
        private int commandID = 0;
        private long lastMessagesMillis = 0;
        private string lastOpenOrdersStr = "";
        private string lastMessagesStr = "";
        private string lastMarketDataStr = "";
        private string lastBarDataStr = "";
        private string lastHistoricDataStr = "";
        private string lastHistoricTradesStr = "";

        public JObject openOrders = new JObject();
		public JObject accountInfo = new JObject();
        public JObject marketData = new JObject();
        public JObject barData = new JObject();
        public JObject historicData = new JObject();
        public JObject historicTrades = new JObject();

        private JObject lastBarData = new JObject();
        private JObject lastMarketData = new JObject();

        public bool ACTIVE = true;
        private bool START = false;

        private Thread openOrdersThread;
        private Thread messageThread;
        private Thread marketDataThread;
        private Thread barDataThread;
        private Thread historicDataThread;

        public Client(EventHandler eventHandler, string MetaTraderDirPath, int sleepDelay, int maxRetryCommandSeconds, bool loadOrdersFromFile, bool verbose)
        {
            this.eventHandler = eventHandler;
            this.MetaTraderDirPath = MetaTraderDirPath;
            this.sleepDelay = sleepDelay;
            this.maxRetryCommandSeconds = maxRetryCommandSeconds;
            this.loadOrdersFromFile = loadOrdersFromFile;
            this.verbose = verbose;

            if (!Directory.Exists(MetaTraderDirPath))
            {
                print("ERROR: MetaTraderDirPath does not exist! MetaTraderDirPath: " + MetaTraderDirPath);
                Environment.Exit(1);
            }

            this.pathOrders = Path.Join(MetaTraderDirPath, "DWX", "DWX_Orders.txt");
            this.pathMessages = Path.Join(MetaTraderDirPath, "DWX", "DWX_Messages.txt");
            this.pathMarketData = Path.Join(MetaTraderDirPath, "DWX", "DWX_Market_Data.txt");
            this.pathBarData = Path.Join(MetaTraderDirPath, "DWX", "DWX_Bar_Data.txt");
            this.pathHistoricData = Path.Join(MetaTraderDirPath, "DWX", "DWX_Historic_Data.txt");
            this.pathHistoricTrades = Path.Join(MetaTraderDirPath, "DWX", "DWX_Historic_Trades.txt");
            this.pathOrdersStored = Path.Join(MetaTraderDirPath, "DWX", "DWX_Orders_Stored.txt");
            this.pathMessagesStored = Path.Join(MetaTraderDirPath, "DWX", "DWX_Messages_Stored.txt");
            this.pathCommandsPrefix = Path.Join(MetaTraderDirPath, "DWX", "DWX_Commands_");

            loadMessages();

            if (loadOrdersFromFile)
               loadOrders();

            this.openOrdersThread = new Thread(() => checkOpenOrders());
            this.openOrdersThread.Start();

            this.messageThread = new Thread(() => checkMessages());
            this.messageThread.Start();

            this.marketDataThread = new Thread(() => checkMarketData());
            this.marketDataThread.Start();

            this.barDataThread = new Thread(() => checkBarData());
            this.barDataThread.Start();

            this.historicDataThread = new Thread(() => checkHistoricData());
            this.historicDataThread.Start();

            resetCommandIDs();

            // no need to wait. 
            if (eventHandler == null)
            {
                start();
            }
            else
            {
                Thread.Sleep(1000);
                start();
                eventHandler.start(this);
            }
        }

		/*START can be used to check if the client has been initialized.  
		*/
        public void start()
        {
            START = true;
        }
		

		/*Regularly checks the file for open orders and triggers
		the eventHandler.onOrderEvent() function.
		*/
        private void checkOpenOrders()
        {
            while (ACTIVE)
            {

                Thread.Sleep(sleepDelay);

                if (!START)
                    continue;

                string text = tryReadFile(pathOrders);

                if (text.Length == 0 || text.Equals(lastOpenOrdersStr))
                    continue;
                
                lastOpenOrdersStr = text;

                JObject data;

                try
                {
                    data = JObject.Parse(text);
                }
                catch
                {
                    continue;
                }

                if (data == null)
                    continue;
                
				JObject dataOrders = (JObject)data["orders"];
				
                bool newEvent = false;
                foreach (var x in openOrders)
                {
                    // JToken value = x.Value;
                    if (dataOrders[x.Key] == null)
                    {
                        newEvent = true;
                        if (verbose)
                            print("Order removed: " + openOrders[x.Key].ToString());
                    }
                }
                foreach (var x in dataOrders)
                {
                    // JToken value = x.Value;
                    if (openOrders[x.Key] == null)
                    {
                        newEvent = true;
                        if (verbose)
                            print("New order: " + dataOrders[x.Key].ToString());
                    }
                }
				
                openOrders = dataOrders;
				accountInfo = (JObject)data["account_info"];

                if (loadOrdersFromFile)
                    tryWriteToFile(pathOrdersStored, data.ToString());

                if (eventHandler != null && newEvent)
                    eventHandler.onOrderEvent(this);
            }
        }
		

		/*Regularly checks the file for messages and triggers
		the eventHandler.onMessage() function.
		*/
        private void checkMessages()
        {
            while (ACTIVE)
            {

                Thread.Sleep(sleepDelay);

                if (!START)
                    continue;

                string text = tryReadFile(pathMessages);

                if (text.Length == 0 || text.Equals(lastMessagesStr))
                    continue;

                lastMessagesStr = text;

                JObject data;

                try
                {
                    data = JObject.Parse(text);
                }
                catch
                {
                    continue;
                }

                if (data == null)
                    continue;

                // var sortedObj = new JObject(data.Properties().OrderByDescending(p => (int)p.Value));

                // make sure that the message are sorted so that we don't miss messages because of (millis > lastMessagesMillis).
                ArrayList millisList = new ArrayList();

                foreach (var x in data)
                {
                    if (data[x.Key] != null)
                    {
                        millisList.Add(x.Key);
                    }
                }
                millisList.Sort();
                foreach (string millisStr in millisList)
                {
                    if (data[millisStr] != null) 
                    {
                        long millis = Int64.Parse(millisStr);
                        if (millis > lastMessagesMillis)
                        {
                            lastMessagesMillis = millis;
                            if (eventHandler != null)
                                eventHandler.onMessage(this, (JObject)data[millisStr]);
                        }
                    }
                }
                tryWriteToFile(pathMessagesStored, data.ToString());
            }
        }
		

		/*Regularly checks the file for market data and triggers
		the eventHandler.onTick() function.
		*/
        private void checkMarketData()
        {
            while (ACTIVE)
            {

                Thread.Sleep(sleepDelay);

                if (!START)
                    continue;

                string text = tryReadFile(pathMarketData);

                if (text.Length == 0 || text.Equals(lastMarketDataStr))
                    continue;

                lastMarketDataStr = text;

                JObject data;

                try
                {
                    data = JObject.Parse(text);
                }
                catch
                {
                    continue;
                }

                if (data == null)
                    continue;

                marketData = data;

                if (eventHandler != null)
                {
                    foreach (var x in marketData)
                    {
                        string symbol = x.Key;
                        if (lastMarketData[symbol] == null || !marketData[symbol].Equals(lastMarketData[symbol]))
                        {
                            // JObject jo = (JObject)marketData[symbol];
                            eventHandler.onTick(this, symbol, 
                                                (double)marketData[symbol]["bid"], 
                                                (double)marketData[symbol]["ask"]);
                        }
                    }
                }
                lastMarketData = data;
            }
        }
		

		/*Regularly checks the file for bar data and triggers
		the eventHandler.onBarData() function.
		*/
        private void checkBarData()
        {
            while (ACTIVE)
            {

                Thread.Sleep(sleepDelay);

                if (!START)
                    continue;

                string text = tryReadFile(pathBarData);

                if (text.Length == 0 || text.Equals(lastBarDataStr))
                    continue;

                lastBarDataStr = text;

                JObject data;

                try
                {
                    data = JObject.Parse(text);
                }
                catch
                {
                    continue;
                }

                if (data == null)
                    continue;

                barData = data;

                if (eventHandler != null)
                {
                    foreach (var x in barData)
                    {
                        string st = x.Key;
                        if (lastBarData[st] == null || !barData[st].Equals(lastBarData[st]))
                        {
                            string[] stSplit = st.Split("_");
                            if (stSplit.Length != 2)
                                continue;
                            // JObject jo = (JObject)barData[symbol];
                            eventHandler.onBarData(this, stSplit[0], stSplit[1], 
                                                   (String)barData[st]["time"], 
                                                   (double)barData[st]["open"], 
                                                   (double)barData[st]["high"], 
                                                   (double)barData[st]["low"], 
                                                   (double)barData[st]["close"], 
                                                   (int)barData[st]["tick_volume"]);
                        }
                    }
                }
                lastBarData = data;
            }
        }
		

		/*Regularly checks the file for historic data and triggers
		the eventHandler.onHistoricData() function.
		*/
        private void checkHistoricData()
        {
            while (ACTIVE)
            {

                Thread.Sleep(sleepDelay);

                if (!START)
                    continue;

                string text = tryReadFile(pathHistoricData);

                if (text.Length > 0 && !text.Equals(lastHistoricDataStr))
                {
                    lastHistoricDataStr = text;

                    JObject data;

                    try
                    {
                        data = JObject.Parse(text);
                    }
                    catch
                    {
                        data = null;
                    }

                    if (data != null)
                    {
                        foreach (var x in data)
                        {
                            historicData[x.Key] = data[x.Key];
                        }

                        tryDeleteFile(pathHistoricData);

                        if (eventHandler != null)
                        {
                            foreach (var x in data)
                            {
                                string st = x.Key;
                                string[] stSplit = st.Split("_");
                                if (stSplit.Length != 2)
                                    continue;
                                // JObject jo = (JObject)barData[symbol];
                                eventHandler.onHistoricData(this, stSplit[0], stSplit[1], (JObject)data[x.Key]);
                            }
                        }
                    }

                    
                }

                // also check historic trades in the same thread. 
                text = tryReadFile(pathHistoricTrades);

                if (text.Length > 0 && !text.Equals(lastHistoricTradesStr))
                {
                    lastHistoricTradesStr = text;

                    JObject data;

                    try
                    {
                        data = JObject.Parse(text);
                    }
                    catch
                    {
                        data = null;
                    }

                    if (data != null)
                    {
                        historicTrades = data;

                        tryDeleteFile(pathHistoricTrades);

                        if (eventHandler != null)
                            eventHandler.onHistoricTrades(this);
                    }

                    
                }
            }
        }
		

		/*Loads stored orders from file (in case of a restart). 
		*/
        private void loadOrders()
        {

            string text = tryReadFile(pathOrdersStored);

            if (text.Length == 0)
                return;

            JObject data;

            try
            {
				data = JObject.Parse(text);
            }
            catch
            {
                return;
            }

            if (data == null)
                return;

            lastOpenOrdersStr = text;
			openOrders = (JObject)data["orders"];
			accountInfo = (JObject)data["account_info"];
        }
		

		/*Loads stored messages from file (in case of a restart). 
		*/
        private void loadMessages()
        {

            string text = tryReadFile(pathMessagesStored);
			
            if (text.Length == 0)
                return;
			
            JObject data;

            try
            {
                data = JObject.Parse(text);
            }
            catch (Exception e)
            {	
				print(e.ToString());
                return;
            }

            if (data == null)
                return;
			
            lastMessagesStr = text;

            // here we don't have to sort because we just need the latest millis value. 
            foreach (var x in data)
            {
                long millis = Int64.Parse(x.Key);
                if (millis > lastMessagesMillis)
                    lastMessagesMillis = millis;
            }
        }
		

		/*Sends a SUBSCRIBE_SYMBOLS command to subscribe to market (tick) data.

		Args:
			symbols (String[]): List of symbols to subscribe to.
		
		Returns:
			null

			The data will be stored in marketData. 
			On receiving the data the eventHandler.onTick() 
			function will be triggered. 
		*/
        public void subscribeSymbols(string[] symbols)
        {
            sendCommand("SUBSCRIBE_SYMBOLS", String.Join(",", symbols));
        }
		

        /*Sends a SUBSCRIBE_SYMBOLS_BAR_DATA command to subscribe to bar data.

		Args:
			symbols (string[,]): List of lists containing symbol/time frame 
			combinations to subscribe to. For example:
			string[,] symbols = new string[,]{{"EURUSD", "M1"}, {"USDJPY", "H1"}};
		
		Returns:
			null

			The data will be stored in barData. 
			On receiving the data the eventHandler.onBarData() 
			function will be triggered. 
		*/
        public void subscribeSymbolsBarData(string[,] symbols)
        {
            string content = "";
            for (int i = 0; i < symbols.GetLength(0); i++)
            {
                if (i != 0) content += ",";
                content += symbols[i, 0] + "," + symbols[i, 1];
            }
            sendCommand("SUBSCRIBE_SYMBOLS_BAR_DATA", content);
        }
		

		/*Sends a GET_HISTORIC_DATA command to request historic data.
		
		Args:
			symbol (String): Symbol to get historic data.
			timeFrame (String): Time frame for the requested data.
			start (long): Start timestamp (seconds since epoch) of the requested data.
			end (long): End timestamp of the requested data.
		
		Returns:
			null

			The data will be stored in historicData. 
			On receiving the data the eventHandler.onHistoricData() 
			function will be triggered. 
		*/
		public void getHistoricData(String symbol, String timeFrame, long start, long end)
		{
			string content = symbol + "," + timeFrame + "," + start + "," + end;
            sendCommand("GET_HISTORIC_DATA", content);
		}



        /*Sends a GET_HISTORIC_TRADES command to request historic trades.
    
        Kwargs:
            lookbackDays (int): Days to look back into the trade history. 
		                        The history must also be visible in MT4. 
    
        Returns:
            None

            The data will be stored in historicTrades. 
            On receiving the data the eventHandler.onHistoricTrades() 
            function will be triggered. 
        */
        public void getHistoricTrades(int lookbackDays)
        {
            sendCommand("GET_HISTORIC_TRADES", lookbackDays.ToString());
        }


        /*Sends an OPEN_ORDER command to open an order.

		Args:
			symbol (String): Symbol for which an order should be opened. 
			order_type (String): Order type. Can be one of:
				'buy', 'sell', 'buylimit', 'selllimit', 'buystop', 'sellstop'
			lots (double): Volume in lots
			price (double): Price of the (pending) order. Can be zero 
				for market orders. 
			stop_loss (double): SL as absoute price. Can be zero 
				if the order should not have an SL. 
			take_profit (double): TP as absoute price. Can be zero 
				if the order should not have a TP.  
			magic (int): Magic number
			comment (String): Order comment
			expriation (long): Expiration time given as timestamp in seconds. 
				Can be zero if the order should not have an expiration time.  
		*/
        public void openOrder(string symbol, string orderType, double lots, double price, double stopLoss, double takeProfit, int magic, string comment, long expiration)
        {
            string content = symbol + "," + orderType + "," + format(lots) + "," + format(price) + "," + format(stopLoss) + "," + format(takeProfit) + "," + magic + "," + comment + "," + expiration;
            sendCommand("OPEN_ORDER", content);
        }
		

		/*Sends a MODIFY_ORDER command to modify an order.

		Args:
			ticket (int): Ticket of the order that should be modified.
			lots (double): Volume in lots
			price (double): Price of the (pending) order. Non-zero only 
				works for pending orders. 
			stop_loss (double): New stop loss price.
			take_profit (double): New take profit price. 
			expriation (long): New expiration time given as timestamp in seconds. 
				Can be zero if the order should not have an expiration time. 
		*/
        public void modifyOrder(int ticket, double lots, double price, double stopLoss, double takeProfit, long expiration)
        {
            string content = ticket + "," + format(lots) + "," + format(price) + "," + format(stopLoss) + "," + format(takeProfit) + "," + expiration;
            sendCommand("MODIFY_ORDER", content);
        }
		

        /*Sends a CLOSE_ORDER command to close an order.

		Args:
			ticket (int): Ticket of the order that should be closed.
			lots (double): Volume in lots. If lots=0 it will try to 
				close the complete position. 
		*/
        public void closeOrder(int ticket, double lots=0)
        {
            string content = ticket + "," + format(lots);
            sendCommand("CLOSE_ORDER", content);
        }
		

        /*Sends a CLOSE_ALL_ORDERS command to close all orders
		with a given symbol.

		Args:
			symbol (str): Symbol for which all orders should be closed. 
		*/
        public void closeAllOrders()
        {
            sendCommand("CLOSE_ALL_ORDERS", "");
        }
		

        /*Sends a CLOSE_ORDERS_BY_SYMBOL command to close all orders
		with a given symbol.

		Args:
			symbol (str): Symbol for which all orders should be closed. 
		*/
        public void closeOrdersBySymbol(string symbol)
        {
            sendCommand("CLOSE_ORDERS_BY_SYMBOL", symbol);
        }
		

        /*Sends a CLOSE_ORDERS_BY_MAGIC command to close all orders
		with a given magic number.

		Args:
			magic (str): Magic number for which all orders should 
				be closed. 
		*/
        public void closeOrdersByMagic(int magic)
        {
            sendCommand("CLOSE_ORDERS_BY_MAGIC", magic.ToString());
        }

        /*Sends a RESET_COMMAND_IDS command to reset stored command IDs. 
        This should be used when restarting the java side without restarting 
        the mql side.
        */
        public void resetCommandIDs() 
        {
            commandID = 0;
            
            sendCommand("RESET_COMMAND_IDS", "");

            // sleep to make sure it is read before other commands.
            Thread.Sleep(500);
        }


		/*Sends a command to the mql server by writing it to 
		one of the command files. 

		Multiple command files are used to allow for fast execution 
		of multiple commands in the correct chronological order. 
		*/
        void sendCommand(string command, string content)
        {
            // Need lock so that different threads do not use the same 
            // commandID or write at the same time.
            lock (this) {
                commandID = (commandID + 1) % 100000;

                string text = "<:" + commandID + "|" + command + "|" + content + ":>";

                DateTime now = DateTime.UtcNow;
                DateTime endTime = DateTime.UtcNow + new TimeSpan(0, 0, maxRetryCommandSeconds);

                // trying again for X seconds in case all files exist or are 
                // currently read from mql side. 
                while (now < endTime)
                {
                    // using 10 different files to increase the execution speed 
                    // for muliple commands. 
                    bool success = false;
                    for (int i = 0; i < maxCommandFiles; i++)
                    {
                        string filePath = pathCommandsPrefix + i + ".txt";
                        if (!File.Exists(filePath) && tryWriteToFile(filePath, text)) 
                        {
                            success = true;
                            break;
                        }
                    }
                    if (success) break;
                    Thread.Sleep(sleepDelay);
                    now = DateTime.UtcNow;
                }
            }
        }
    }
}
