# ThorlabsImagerPython

## Setup

### Prerequisites

- ThorImage OCT v5.8 or later installed
- Python v3.11 or later installed

### Installation

1. Locate the wheel file at  
   `C:\Program Files\Thorlabs\SpectralRadar\Python\PySpectralRadar\lib\pyspectralradar-5.8.0-py3-none-any.whl`
2. Install the SDK manually:
   ```
   pip install "C:\\Program Files\\Thorlabs\\SpectralRadar\\Python\\PySpectralRadar\\lib\\pyspectralradar-5.8.0-py3-none-any.whl"
   ```
3. (Optional) Create and activate a virtual environment:
   ```powershell
   python -m venv venv
   .\venv\Scripts\activate
   ```
4. Install other dependencies that may be needed:
   ```powershell
   # From the current directory:
   pip install -r requirements.txt

   # Or using the full path:
   pip install -r "C:\\Users\\alber\\myOCT\\ThorlabsImagerPython\\requirements.txt"
   ```