
import os
import json
from time import sleep
from threading import Thread
from os.path import join, exists
from traceback import print_exc
from datetime import datetime, timedelta


"""Client class

This class includes all of the functions needed for communication with MT4/MT5. 

"""


class dwx_client():

    def __init__(self, event_handler=None, metatrader_dir_path='', 
                 sleep_delay=0.005,             # 5 ms for time.sleep()
                 max_retry_command_seconds=10,  # retry to send the commend for 10 seconds if not successful. 
                 load_orders_from_file=True,    # to load orders from file on initialization. 
                 verbose=True
                 ):

        self.event_handler = event_handler
        self.sleep_delay = sleep_delay
        self.max_retry_command_seconds = max_retry_command_seconds
        self.load_orders_from_file = load_orders_from_file
        self.verbose = verbose

        if not exists(metatrader_dir_path):
            print('ERROR: metatrader_dir_path does not exist!')
            exit()

        self.path_orders = join(metatrader_dir_path, 
                                'DWX', 'DWX_Orders.txt')
        self.path_messages = join(metatrader_dir_path, 
                                  'DWX', 'DWX_Messages.txt')
        self.path_market_data = join(metatrader_dir_path, 
                                     'DWX', 'DWX_Market_Data.txt')
        self.path_bar_data = join(metatrader_dir_path, 
                                  'DWX', 'DWX_Bar_Data.txt')
        self.path_historic_data = join(metatrader_dir_path, 
                                       'DWX', 'DWX_Historic_Data.txt')
        self.path_historic_trades = join(metatrader_dir_path, 
                                       'DWX', 'DWX_Historic_Trades.txt')
        self.path_orders_stored = join(metatrader_dir_path, 
                                       'DWX', 'DWX_Orders_Stored.txt')
        self.path_messages_stored = join(metatrader_dir_path, 
                                    'DWX', 'DWX_Messages_Stored.txt')
        self.path_commands_prefix = join(metatrader_dir_path, 
                                         'DWX', 'DWX_Commands_')
        
        self.num_command_files = 50

        self._last_messages_millis = 0
        self._last_open_orders_str = ""
        self._last_messages_str = ""
        self._last_market_data_str = ""
        self._last_bar_data_str = ""
        self._last_historic_data_str = ""
        self._last_historic_trades_str = ""

        self.open_orders = {}
        self.account_info = {}
        self.market_data = {}
        self.bar_data = {}
        self.historic_data = {}
        self.historic_trades = {}

        self._last_bar_data = {}
        self._last_market_data = {}

        self.ACTIVE = True
        self.START = False

        self.load_messages()
        
        if self.load_orders_from_file:
            self.load_orders()

        self.messages_thread = Thread(target=self.check_messages, args=())
        self.messages_thread.daemon = True
        self.messages_thread.start()

        self.market_data_thread = Thread(target=self.check_market_data, args=())
        self.market_data_thread.daemon = True
        self.market_data_thread.start()

        self.bar_data_thread = Thread(target=self.check_bar_data, args=())
        self.bar_data_thread.daemon = True
        self.bar_data_thread.start()

        self.open_orders_thread = Thread(target=self.check_open_orders, args=())
        self.open_orders_thread.daemon = True
        self.open_orders_thread.start()

        self.historic_data_thread = Thread(target=self.check_historic_data, args=())
        self.historic_data_thread.daemon = True
        self.historic_data_thread.start()
        
        # no need to wait. 
        if self.event_handler is None:
            self.start()


    """START can be used to check if the client has been initialized.  
    """
    def start(self):
        self.START = True
    

    """Tries to read a file. 
    """
    def try_read_file(self, file_path):

        try:
            if exists(file_path):
                with open(file_path) as f:
                    text = f.read()
                return text
        # can happen if mql writes to the file. don't print anything here. 
        except (IOError, PermissionError):
            pass
        except:
            print_exc()
        return ''
    

    """Tries to remove a file.
    """
    def try_remove_file(self, file_path):
        for _ in range(10):
            try:
                os.remove(file_path)
                break
            except (IOError, PermissionError):
                pass
            except:
                print_exc()


    """Regularly checks the file for open orders and triggers
    the event_handler.on_order_event() function.
    """
    def check_open_orders(self):

        while self.ACTIVE:

            sleep(self.sleep_delay)
            
            if not self.START:
                continue

            text = self.try_read_file(self.path_orders)

            if len(text.strip()) == 0 or text == self._last_open_orders_str:
                continue

            self._last_open_orders_str = text
            data = json.loads(text)
            
            new_event = False
            for order_id, order in self.open_orders.items():
                # also triggers if a pending order got filled?
                if order_id not in data['orders'].keys():
                    new_event = True
                    if self.verbose:
                        print('Order removed: ' , order)
            
            for order_id, order in data['orders'].items():
                if order_id not in self.open_orders:
                    new_event = True
                    if self.verbose:
                        print('New order: ' , order)
            
            self.account_info = data['account_info']
            self.open_orders = data['orders']

            if self.load_orders_from_file:
                with open(self.path_orders_stored, 'w') as f:
                    f.write(json.dumps(data))

            if self.event_handler is not None and new_event:
                self.event_handler.on_order_event()


    """Regularly checks the file for messages and triggers
    the event_handler.on_message() function.
    """
    def check_messages(self):

        while self.ACTIVE:
            
            sleep(self.sleep_delay)

            if not self.START:
                continue

            text = self.try_read_file(self.path_messages)

            if len(text.strip()) == 0 or text == self._last_messages_str:
                continue

            self._last_messages_str = text
            data = json.loads(text)

            # use sorted() to make sure that we don't miss messages 
            # because of (int(millis) > self._last_messages_millis). 
            for millis, message in sorted(data.items()):
                if int(millis) > self._last_messages_millis:
                    self._last_messages_millis = int(millis)
                    # print(message)
                    if self.event_handler is not None:
                        self.event_handler.on_message(message)
            
            with open(self.path_messages_stored, 'w') as f:
                f.write(json.dumps(data))


    """Regularly checks the file for market data and triggers
    the event_handler.on_tick() function.
    """
    def check_market_data(self):

        while self.ACTIVE:

            sleep(self.sleep_delay)

            if not self.START:
                continue

            text = self.try_read_file(self.path_market_data)

            if len(text.strip()) == 0 or text == self._last_market_data_str:
                continue

            self._last_market_data_str = text
            data = json.loads(text)
            
            self.market_data = data

            if self.event_handler is not None:
                for symbol in data.keys():
                    if symbol not in self._last_market_data or self.market_data[symbol] != self._last_market_data[symbol]:
                        self.event_handler.on_tick(symbol, 
                                                   self.market_data[symbol]['bid'], 
                                                   self.market_data[symbol]['ask'])
            self._last_market_data = data
    
    
    """Regularly checks the file for bar data and triggers
    the event_handler.on_bar_data() function.
    """
    def check_bar_data(self):

        while self.ACTIVE:

            sleep(self.sleep_delay)

            if not self.START:
                continue

            text = self.try_read_file(self.path_bar_data)

            if len(text.strip()) == 0 or text == self._last_bar_data_str:
                continue
            
            self._last_bar_data_str = text
            data = json.loads(text)

            self.bar_data = data

            if self.event_handler is not None:
                for st in data.keys():
                    if st not in self._last_bar_data or self.bar_data[st] != self._last_bar_data[st]:
                        symbol, time_frame = st.split('_')
                        self.event_handler.on_bar_data(symbol, 
                                                    time_frame, 
                                                    self.bar_data[st]['time'], 
                                                    self.bar_data[st]['open'], 
                                                    self.bar_data[st]['high'], 
                                                    self.bar_data[st]['low'], 
                                                    self.bar_data[st]['close'], 
                                                    self.bar_data[st]['tick_volume'])
            self._last_bar_data = data
    

    """Regularly checks the file for historic data and trades and triggers
    the event_handler.on_historic_data() function.
    """
    def check_historic_data(self):

        while self.ACTIVE:

            sleep(self.sleep_delay)

            if not self.START:
                continue

            text = self.try_read_file(self.path_historic_data)

            if len(text.strip()) > 0 and text != self._last_historic_data_str:
                
                self._last_historic_data_str = text

                data = json.loads(text)
                
                for st in data.keys():
                    self.historic_data[st] = data[st]
                    if self.event_handler is not None:
                        symbol, time_frame = st.split('_')
                        self.event_handler.on_historic_data(symbol, time_frame, data[st])
                
                self.try_remove_file(self.path_historic_data)


            # also check historic trades in the same thread. 
            text = self.try_read_file(self.path_historic_trades)

            if len(text.strip()) > 0 and text != self._last_historic_trades_str:
            
                self._last_historic_trades_str = text

                data = json.loads(text)
                
                self.historic_trades = data
                self.event_handler.on_historic_trades()
                
                self.try_remove_file(self.path_historic_trades)
    

    """Loads stored orders from file (in case of a restart). 
    """
    def load_orders(self):

        text = self.try_read_file(self.path_orders_stored)
        
        if len(text) > 0:
            self._last_open_orders_str = text
            data = json.loads(text)
            self.account_info = data['account_info']
            self.open_orders = data['orders']
    

    """Loads stored messages from file (in case of a restart). 
    """
    def load_messages(self):

        text = self.try_read_file(self.path_messages_stored)
        
        if len(text) > 0:

            self._last_messages_str = text
            
            data = json.loads(text)
            
            # here we don't have to sort because we just need the latest millis value. 
            for millis in data.keys():
                if int(millis) > self._last_messages_millis:
                    self._last_messages_millis = int(millis)
    

    """Sends a SUBSCRIBE_SYMBOLS command to subscribe to market (tick) data.

    Args:
        symbols (list[str]): List of symbols to subscribe to.
    
    Returns:
        None

        The data will be stored in self.market_data. 
        On receiving the data the event_handler.on_tick() 
        function will be triggered. 
    
    """
    def subscribe_symbols(self, symbols):
        
        self.send_command('SUBSCRIBE_SYMBOLS', ','.join(symbols))
    

    """Sends a SUBSCRIBE_SYMBOLS_BAR_DATA command to subscribe to bar data.

    Kwargs:
        symbols (list[list[str]]): List of lists containing symbol/time frame 
        combinations to subscribe to. For example:
        symbols = [['EURUSD', 'M1'], ['GBPUSD', 'H1']]
    
    Returns:
        None

        The data will be stored in self.bar_data. 
        On receiving the data the event_handler.on_bar_data() 
        function will be triggered. 
    
    """
    def subscribe_symbols_bar_data(self, symbols=[['EURUSD', 'M1']]):

        data = [f'{st[0]},{st[1]}' for st in symbols]
        self.send_command('SUBSCRIBE_SYMBOLS_BAR_DATA', ','.join(str(p) for p in data))


    """Sends a GET_HISTORIC_DATA command to request historic data. 
    
    Kwargs:
        symbol (str): Symbol to get historic data.
        time_frame (str): Time frame for the requested data.
        start (int): Start timestamp (seconds since epoch) of the requested data.
        end (int): End timestamp of the requested data.
    
    Returns:
        None

        The data will be stored in self.historic_data. 
        On receiving the data the event_handler.on_historic_data()
        function will be triggered. 
    """
    def get_historic_data(self,
                    symbol='EURUSD',
                    time_frame='D1',
                    start=(datetime.utcnow() - timedelta(days=30)).timestamp(),
                    end=datetime.utcnow().timestamp()):
        
        # start_date.strftime('%Y.%m.%d %H:%M:00')
        data = [symbol, time_frame, 
                int(start), 
                int(end)]
        self.send_command('GET_HISTORIC_DATA', ','.join(str(p) for p in data))
    

    """Sends a GET_HISTORIC_TRADES command to request historic trades.
    
    Kwargs:
        lookback_days (int): Days to look back into the trade history. The history must also be visible in MT4. 
    
    Returns:
        None

        The data will be stored in self.historic_trades. 
        On receiving the data the event_handler.on_historic_trades() 
        function will be triggered. 
    """
    def get_historic_trades(self,
                    lookback_days=30):
        
        self.send_command('GET_HISTORIC_TRADES', str(lookback_days))

    
    """Sends an OPEN_ORDER command to open an order.

    Kwargs:
        symbol (str): Symbol for which an order should be opened. 
        order_type (str): Order type. Can be one of:
            'buy', 'sell', 'buylimit', 'selllimit', 'buystop', 'sellstop'
        lots (float): Volume in lots
        price (float): Price of the (pending) order. Can be zero 
            for market orders. 
        stop_loss (float): SL as absoute price. Can be zero 
            if the order should not have an SL. 
        take_profit (float): TP as absoute price. Can be zero 
            if the order should not have a TP.  
        magic (int): Magic number
        comment (str): Order comment
        expriation (int): Expiration time given as timestamp in seconds. 
            Can be zero if the order should not have an expiration time.  
    
    """
    def open_order(self, symbol='EURUSD', 
                   order_type='buy',
                   lots=0.01,
                   price=0,
                   stop_loss=0,
                   take_profit=0,
                   magic=0, 
                   comment='', 
                   expriation=0):

        data = [symbol, order_type, lots, price, stop_loss, take_profit, magic, comment, expriation]
        self.send_command('OPEN_ORDER', ','.join(str(p) for p in data))


    """Sends a MODIFY_ORDER command to modify an order.

    Args:
        ticket (int): Ticket of the order that should be modified.
    
    Kwargs:
        lots (float): Volume in lots
        price (float): Price of the (pending) order. Non-zero only 
            works for pending orders. 
        stop_loss (float): New stop loss price.
        take_profit (float): New take profit price. 
        expriation (int): New expiration time given as timestamp in seconds. 
            Can be zero if the order should not have an expiration time. 
    
    """
    def modify_order(self, ticket,
                   lots=0.01,
                   price=0,
                   stop_loss=0,
                   take_profit=0,
                   expriation=0):

        data = [ticket, lots, price, stop_loss, take_profit, expriation]
        self.send_command('MODIFY_ORDER', ','.join(str(p) for p in data))


    """Sends a CLOSE_ORDER command to close an order.

    Args:
        ticket (int): Ticket of the order that should be closed.
    
    Kwargs:
        lots (float): Volume in lots. If lots=0 it will try to 
            close the complete position. 
    
    """
    # 
    def close_order(self, ticket, lots=0):

        data = [ticket, lots]
        self.send_command('CLOSE_ORDER', ','.join(str(p) for p in data))
    
    
    """Sends a CLOSE_ALL_ORDERS command to close all orders.
    """
    def close_all_orders(self):

        self.send_command('CLOSE_ALL_ORDERS', '')


    """Sends a CLOSE_ORDERS_BY_SYMBOL command to close all orders
    with a given symbol.

    Args:
        symbol (str): Symbol for which all orders should be closed. 
    
    """
    def close_orders_by_symbol(self, symbol):
        
        self.send_command('CLOSE_ORDERS_BY_SYMBOL', symbol)
    

    """Sends a CLOSE_ORDERS_BY_MAGIC command to close all orders
    with a given magic number.

    Args:
        magic (str): Magic number for which all orders should 
            be closed. 
    
    """
    def close_orders_by_magic(self, magic):

        self.send_command('CLOSE_ORDERS_BY_MAGIC', magic)


    """Sends a command to the mql server by writing it to 
    one of the command files. 

    Multiple command files are used to allow for fast execution 
    of multiple commands in the correct chronological order. 
    
    """
    def send_command(self, command, content):

        end_time = datetime.utcnow() + timedelta(seconds=self.max_retry_command_seconds)
        now = datetime.utcnow()

        # trying again for X seconds in case all files exist or are currently read from mql side. 
        while now < end_time:
            # using 10 different files to increase the execution speed for muliple commands. 
            for i in range(self.num_command_files):
                # only send commend if the file does not exists so that we do not overwrite all commands. 
                file_path = f'{self.path_commands_prefix}{i}.txt'
                if not exists(file_path):
                    try:
                        with open(file_path, 'w') as f:
                            f.write(f'<:{command}|{content}:>')
                            return
                    except:
                        print_exc()
            sleep(self.sleep_delay)
            now = datetime.utcnow()

