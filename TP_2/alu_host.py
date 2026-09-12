import tkinter as tk
from tkinter import ttk, messagebox
import serial
import serial.tools.list_ports
import threading


# BACKEND: SERIAL PORT MANAGER
class SerialManager:
    def __init__(self, on_receive_callback):
        self.serial_port = serial.Serial()
        self.on_receive_callback = on_receive_callback
        self.is_running = False

    def connect(self, port_name, baudrate=9600):
        try:
            self.serial_port.port = port_name
            self.serial_port.baudrate = baudrate
            self.serial_port.timeout = 1
            self.serial_port.open()
            self.is_running = True
            # starts a secondary thread to listen without freezing the app
            threading.Thread(target=self._listen, daemon=True).start()
            return True
        except Exception as e:
            return str(e)

    def disconnect(self):
        self.is_running = False
        if self.serial_port.is_open:
            self.serial_port.close()

    def send_byte(self, byte_value):
        if self.serial_port.is_open:
            try:
                self.serial_port.write(bytes([byte_value]))
            except Exception as e:
                print(f"Error sending: {e}")

    def _listen(self):
        while self.is_running and self.serial_port.is_open:
            try:
                if self.serial_port.in_waiting > 0:
                    data = self.serial_port.read(1)
                    if data:
                        # notify the GUI that data has arrived
                        self.on_receive_callback(data[0])
            except:
                break

# FRONTEND: PRAPHICAL USER INTERFACE
class ALUApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ALU Tang Nano 20K - Control Panel")
        self.root.geometry("350x450")
        self.root.resizable(False, False)

        # state variables
        self.rx_value = 0
        self.base_var = tk.StringVar(value="DEC")
        
        # opcode mapping
        self.opcodes = {
            "ADD": 32,
            "SUB": 34,
            "AND": 36,
            "OR":  37,
            "XOR": 38,
            "SRL": 2,
            "SRA": 3
        }

        # initialize backend
        self.sm = SerialManager(self.update_rx_display)
        self._build_ui()

    def _build_ui(self):
        style = ttk.Style()
        style.theme_use('clam')

        # frame: connection
        conn_frame = ttk.Frame(self.root, padding=10)
        conn_frame.pack(fill=tk.X)
        
        self.port_combo = ttk.Combobox(conn_frame, state="readonly", width=15)
        self.port_combo['values'] = [p.device for p in serial.tools.list_ports.comports()]
        if self.port_combo['values']: self.port_combo.current(0)
        self.port_combo.pack(side=tk.LEFT, padx=5)

        self.btn_connect = ttk.Button(conn_frame, text="Connect", command=self.toggle_connection)
        self.btn_connect.pack(side=tk.LEFT)

        # frame: displays (RX and TX)
        disp_frame = ttk.Frame(self.root, padding=10)
        disp_frame.pack(fill=tk.X)

        ttk.Label(disp_frame, text="Received (RX):", font=("Arial", 9)).pack(anchor=tk.W)
        self.lbl_rx = ttk.Label(disp_frame, text="0", font=("Consolas", 16, "bold"), background="#e0e0e0", anchor="e")
        self.lbl_rx.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(disp_frame, text="To send (TX):", font=("Arial", 9)).pack(anchor=tk.W)
        self.entry_tx = ttk.Entry(disp_frame, font=("Consolas", 16), justify="right")
        self.entry_tx.pack(fill=tk.X)
        self.entry_tx.bind('<Return>', lambda e: self.send_tx()) # Send on Enter key

        # frame: base selector
        base_frame = ttk.Frame(self.root, padding=5)
        base_frame.pack(fill=tk.X)
        for base in ["DEC", "HEX", "BIN"]:
            ttk.Radiobutton(base_frame, text=base, value=base, variable=self.base_var, command=self.refresh_displays).pack(side=tk.LEFT, expand=True)

        # frame: buttons (operations)
        btn_frame = ttk.Frame(self.root, padding=10)
        btn_frame.pack(fill=tk.BOTH, expand=True)

        # configure 3 identical columns to distribute space evenly
        for i in range(3):
            btn_frame.columnconfigure(i, weight=1)

        # organizes buttons in rows of 3 using sticky="ew" to stretch them
        row_idx = 0
        col_idx = 0
        for op, code in self.opcodes.items():
            btn = ttk.Button(btn_frame, text=op, command=lambda c=code: self.sm.send_byte(c))
            btn.grid(row=row_idx, column=col_idx, padx=3, pady=3, sticky="ew")
            
            col_idx += 1
            if col_idx > 2: # Move to the next row after the third column
                col_idx = 0
                row_idx += 1
        
        # frame: send button
        btn_send = ttk.Button(self.root, text="SEND NUMBER", command=self.send_tx)
        btn_send.pack(fill=tk.X, padx=10, pady=10)

    # INTERFACE LOGIC
    def toggle_connection(self):
        if not self.sm.is_running:
            port = self.port_combo.get()
            if not port: return
            res = self.sm.connect(port)
            if res is True:
                self.btn_connect.config(text="Disconnect")
            else:
                messagebox.showerror("Error", f"Could not connect: {res}")
        else:
            self.sm.disconnect()
            self.btn_connect.config(text="Connect")

    def send_tx(self):
        txt = self.entry_tx.get().strip()
        if not txt: return
        
        try:
            # parse text based on the selected base
            base = self.base_var.get()
            if base == "DEC":   val = int(txt, 10)
            elif base == "HEX": val = int(txt, 16)
            elif base == "BIN": val = int(txt, 2)

            # limit to 8 bits (0-255)
            if 0 <= val <= 255:
                self.sm.send_byte(val)
                self.entry_tx.delete(0, tk.END) # Clear input
            else:
                messagebox.showwarning("Warning", "The value must be between 0 and 255.")
        except ValueError:
            messagebox.showerror("Error", f"Invalid number for base {base}.")

    def update_rx_display(self, byte_val):
        # since it arrives from a secondary thread, we use after() to safely update the UI
        self.rx_value = byte_val
        self.root.after(0, self.refresh_displays)

    def refresh_displays(self):
        base = self.base_var.get()
        if base == "DEC":   txt = str(self.rx_value)
        elif base == "HEX": txt = f"0x{self.rx_value:02X}"
        elif base == "BIN": txt = f"0b{self.rx_value:08b}"
        
        self.lbl_rx.config(text=txt)

if __name__ == "__main__":
    root = tk.Tk()
    app = ALUApp(root)
    root.mainloop()
