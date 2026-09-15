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

    def send_command(self, target_register, byte_value):
        # sends exactly 2 bytes: target (0=A, 1=B, 2=OP) and value
        if self.serial_port.is_open:
            try:
                self.serial_port.write(bytes([target_register, byte_value]))
            except Exception as e:
                print(f"Error sending: {e}")

    def _listen(self):
        # buffer to store the 5 bytes sent by the FPGA burst
        rx_buffer = []
        while self.is_running and self.serial_port.is_open:
            try:
                if self.serial_port.in_waiting > 0:
                    byte = self.serial_port.read(1)[0]
                    rx_buffer.append(byte)
                    
                    # when all 5 frames arrive, update the UI
                    if len(rx_buffer) == 5:
                        self.on_receive_callback(list(rx_buffer))
                        rx_buffer.clear()
            except:
                break

# FRONTEND: GRAPHICAL USER INTERFACE

class ALUApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ALU Tang Nano 20K - Command Center")
        self.root.resizable(False, False)

        # state variables for RX (A, B, OP, RES, STATUS)
        self.rx_data = [0, 0, 0, 0, 0]
        self.base_var = tk.StringVar(value="DEC")
        
        # target register selection: 0=A, 1=B, 2=OP
        self.target_var = tk.IntVar(value=0)

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

        # frame: FPGA status display (RX)
        disp_frame = ttk.LabelFrame(self.root, text=" FPGA State (RX) ", padding=10)
        disp_frame.pack(fill=tk.X, padx=10, pady=5)

        # dictionary to hold the RX labels
        self.lbls_rx = {}
        row = 0
        for name in ["Reg A", "Reg B", "Reg OP", "ALU Result"]:
            ttk.Label(disp_frame, text=f"{name}:", font=("Arial", 10, "bold")).grid(row=row, column=0, sticky=tk.W, pady=2)
            lbl = ttk.Label(disp_frame, text="0", font=("Consolas", 12), width=15, anchor="e", background="#e0e0e0")
            lbl.grid(row=row, column=1, sticky=tk.E, padx=10, pady=2)
            self.lbls_rx[name] = lbl
            row += 1

        # status bits indicators
        stat_frame = ttk.Frame(disp_frame)
        stat_frame.grid(row=row, column=0, columnspan=2, pady=10)
        self.lbl_c = ttk.Label(stat_frame, text=" C: 0 ", background="gray", foreground="white", font=("Arial", 9, "bold"))
        self.lbl_c.pack(side=tk.LEFT, padx=3)
        self.lbl_z = ttk.Label(stat_frame, text=" Z: 0 ", background="gray", foreground="white", font=("Arial", 9, "bold"))
        self.lbl_z.pack(side=tk.LEFT, padx=3)
        self.lbl_o = ttk.Label(stat_frame, text=" O: 0 ", background="gray", foreground="white", font=("Arial", 9, "bold"))
        self.lbl_o.pack(side=tk.LEFT, padx=3)
        self.lbl_tx = ttk.Label(stat_frame, text=" TX_FULL: 0 ", background="gray", foreground="white", font=("Arial", 9, "bold"))
        self.lbl_tx.pack(side=tk.LEFT, padx=3)

        # frame: data entry (TX)
        tx_frame = ttk.LabelFrame(self.root, text=" Send Data (TX) ", padding=10)
        tx_frame.pack(fill=tk.X, padx=10, pady=5)

        # Radiobuttons for target register
        tgt_frame = ttk.Frame(tx_frame)
        tgt_frame.pack(fill=tk.X, pady=(0, 5))
        ttk.Label(tgt_frame, text="Target:").pack(side=tk.LEFT, padx=(0, 10))
        ttk.Radiobutton(tgt_frame, text="Reg A", value=0, variable=self.target_var).pack(side=tk.LEFT, padx=5)
        ttk.Radiobutton(tgt_frame, text="Reg B", value=1, variable=self.target_var).pack(side=tk.LEFT, padx=5)
        ttk.Radiobutton(tgt_frame, text="Reg OP", value=2, variable=self.target_var).pack(side=tk.LEFT, padx=5)

        self.entry_tx = ttk.Entry(tx_frame, font=("Consolas", 16), justify="right")
        self.entry_tx.pack(fill=tk.X, pady=5)
        self.entry_tx.bind('<Return>', lambda e: self.send_tx())

        # frame: base selector
        base_frame = ttk.Frame(tx_frame, padding=5)
        base_frame.pack(fill=tk.X)
        for base in ["DEC", "HEX", "BIN"]:
            ttk.Radiobutton(base_frame, text=base, value=base, variable=self.base_var, command=self.refresh_displays).pack(side=tk.LEFT, expand=True)

        # frame: operation shortcuts
        btn_frame = ttk.Frame(self.root, padding=10)
        btn_frame.pack(fill=tk.BOTH, expand=True)

        for i in range(3):
            btn_frame.columnconfigure(i, weight=1)

        row_idx, col_idx = 0, 0
        for op, code in self.opcodes.items():
            # send target 2 (OP Code) and the corresponding operation code
            btn = ttk.Button(btn_frame, text=op, command=lambda c=code: self.sm.send_command(2, c))
            btn.grid(row=row_idx, column=col_idx, padx=3, pady=3, sticky="ew")
            col_idx += 1
            if col_idx > 2:
                col_idx = 0
                row_idx += 1
        
        btn_send = ttk.Button(self.root, text="SEND NUMBER", command=self.send_tx)
        btn_send.pack(fill=tk.X, padx=10, pady=5)

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
            base = self.base_var.get()
            if base == "DEC":   val = int(txt, 10)
            elif base == "HEX": val = int(txt, 16)
            elif base == "BIN": val = int(txt, 2)

            if 0 <= val <= 255:
                # sends target byte and value byte
                target = self.target_var.get()
                self.sm.send_command(target, val)
                self.entry_tx.delete(0, tk.END)
            else:
                messagebox.showwarning("Warning", "The value must be between 0 and 255.")
        except ValueError:
            messagebox.showerror("Error", f"Invalid number for base {base}.")

    def update_rx_display(self, rx_buffer):
        self.rx_data = rx_buffer
        self.root.after(0, self.refresh_displays)

    def refresh_displays(self):
        base = self.base_var.get()
        names = ["Reg A", "Reg B", "Reg OP", "ALU Result"]
        
        # update data registers
        for i in range(4):
            val = self.rx_data[i]
            if base == "DEC":   txt = str(val)
            elif base == "HEX": txt = f"0x{val:02X}"
            elif base == "BIN": txt = f"0b{val:08b}"
            self.lbls_rx[names[i]].config(text=txt)
            
        # update status bits (Byte 4)
        stat = self.rx_data[4]
        carry = stat & 1
        zero  = (stat >> 1) & 1
        ovf   = (stat >> 2) & 1
        tx    = (stat >> 3) & 1
        
        self.lbl_c.config(text=f" C: {carry} ", background="green" if carry else "gray")
        self.lbl_z.config(text=f" Z: {zero} ", background="green" if zero else "gray")
        self.lbl_o.config(text=f" O: {ovf} ", background="red" if ovf else "gray")
        self.lbl_tx.config(text=f" TX_FULL: {tx} ", background="orange" if tx else "gray")

if __name__ == "__main__":
    root = tk.Tk()
    app = ALUApp(root)
    root.mainloop()
