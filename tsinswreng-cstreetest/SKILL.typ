#import "@local/tsinswreng-scriptorium:0.1.0": *
#show: _Show


#import "@preview/tsinswreng-auto-heading:0.1.0": auto-heading
#let H = auto-heading;
\-\-\-

name: tsinswreng-cstreetest

description: CsTreeTest測試框架寫法規範

\-\-\-

#H[這份文檔的用途][
	這份文檔規定本項目怎樣使用自研的 `Tsinswreng.CsTreeTest` 測試框架編寫測試。
	讀者對象是新增或維護測試的開發者，以及在項目中工作的 AI。

	文檔按三步展開：先講測試工程的整體結構，再講每一層的寫法，最後講細節、邊界與常見錯誤。
	所有範例代碼按本地源 `0.2.0-alpha` 的 API 寫成。

	讀完之後，讀者應當能夠獨立完成三件事：
	建立一個新的測試工程；為某個被測類補齊測試；判斷一段既有測試代碼屬於哪一代寫法。
]

#H[版本前提][
	`Tsinswreng.CsTreeTest` 目前同時存在兩代 API。兩代的型別名稱與裝配方式都不同，
	混用時編譯不通過。因此動手之前，讀者要先確認目標工程屬於哪一代。

	+ `0.2.0-alpha` 是本地源中的版本，也是本文規範的對象。
	+ `0.1.1-alpha` 已廢棄, 兩版不兼容

]

#H[範式總覽][
	一個測試工程由五層組成，每一層只做一件事：

	+ exe 入口組裝依賴並執行測試。它不碰測試樹的內部結構。
	+ 程序集入口 `XxxTest.MkTree()` 建立根節點，掛上組裝器，返回 `ITestNode`。
	+ 組裝器 `XxxTester` 是 `Tester` 的子類，在 `Init()` 裏把各測試類掛到根節點下。
	+ 測試類主檔 `_TestXxx.cs` 取出被測對象，再把各分片串起來，自身不寫用例。
	+ 分片 `Test<被測函數名>.cs` 只負責往本測試類的節點上掛這個函數的用例。

	把五層的職責連起來看：exe 準備好依賴，程序集入口建立樹，組裝器掛測試類，
	主檔串分片，分片提供用例。

	五層之外，測試工程還需要一個依賴來源 `Di.cs`。
	由用戶業務項目提供,
	非本庫所提供

	除結構之外，本文還規定幾條寫法約定：
	+ 一個被測函數的用例放在一個文件裏，一個被測類的測試放在一個目錄裏。
]

#H[工程級骨架][

	#H[程序集入口][
		程序集入口的職責只有建立根節點與掛上組裝器：

		```cs
		File: MyProj1Test.cs
		using MyProj1.Test.MyDomains.Calculator;
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test;

		// 本程序集對外的入口：只產出測試樹，不執行測試。
		public static class MyProj1Test{
			public static ITestNode MkTree(){
				var Tester = new MyProj1Tester();
				Tester.TestNode = new TestNode{
					// 根節點取程序集名，被上層收編時才不會與上層的根重名。
					UniqName = "MyProj1",
					NonParallelizable = false,//默認即false
					Ordered = false,//默認即false
				};
				Tester.Init();
				// 根節點由本方法手工建立，所以框架不會代為設置這個旗標。
				Tester.Inited = true;
				return Tester.TestNode;
			}
		}

		// 本程序集的組裝器：只掛測試類，不寫用例。
		public class MyProj1Tester : Tester{
			public override void Init(){
				// AddTester 是 ITester 的擴展方法，故顯式用 this 作接收者。
				this.AddTester<TestCalculator>();
			}
		}
		```

		根節點的三個設定各有用途。
		名字用於失敗輸出的路徑。
		`NonParallelizable` 用於整棵子樹都不與別的分支同時跑。
		`Ordered` 用於同一批用例按聲明次序跑。
		這兩者互相獨立，可以同時開啟。
	]

	#H[exe 入口][
		exe 入口放在另一個工程，固定三步，順序不可調換：

		```cs
		File: Program.cs
		using Tsinswreng.CsTreeTest;
		namespace MyProj1.Test.Exe;
		public static class Program{
			public static async Task<int> Main(){
				var Tree = MyProj1Test.MkTree();
				var Summary = await new TreeTestExecutor().RunEtPrint(Tree);
				return Summary.Failed > 0 ? 1 : 0;
			}
		}
		```
	]
]

#H[測試類與分片][
	#H[主檔][
		```cs
		File: MyDomains/Calculator/_TestCalculator.cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test.MyDomains.Calculator;

		// 主檔只做兩件事：取被測對象，把各分片串起來。
		public partial class TestCalculator : Tester{
			//不要寫多餘的沒必要的修飾符 如readonly 之類, 保持更少的代碼字符數
			ICalculator Calculator = Di.GetRSvc<ICalculator>();

			public override void Init(){
				// 分片拿到的是本測試類的節點。
				RegisterAdd(TestNode);
				RegisterTryIntDivide(TestNode);
			}
		}
		```

		每個被測函數的用例寫在各自的分片文件裏。
		因此新增一個被測函數的測試時,
		主檔只加一行 `Register<函數名>(TestNode)`。
	]

	#H[分片][
		`MyDomains/Calculator/TestAdd.cs`
		```cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test.MyDomains.Calculator;

		// 本文件只測 ICalculator.Add 這一個被測函數。
		public partial class TestCalculator{
			public void RegisterAdd(ITestNode Node){
				// 元數據寫一次，之後每條用例只寫名字與函數體。
				var R = Node.MkRegister<TestCalculator>(
					typeof(ICalculator)// 被測類型
					,nameof(ICalculator.Add)// 被測函數名，必須用 nameof
					,"Add:"// 用例名前綴
				).Register;
				var T = Assert.IsTrue;

				R("正數相加", async (O) => {
					T(Calculator.Add(5, 3) == 8, "期望 8");
					T(Calculator.Add(6, 4) == 10, "期望 10");
					return NIL;
				});

				R("正負數相加", async (O) => {
					var Sum = Calculator.Add(5, -3);
					T(Sum == 2, "期望 2，實際 " + Sum);
					return NIL;
				});
			}
		}
		```
	]
]


#H[用例本體][
	用例函數的型別是 `Task<obj?> FnTest(obj? Arg)`。這個型別決定了三件事：

	+ 用例一律是異步的。純同步的邏輯直接返回 `NIL` 即可。
		工程若沒有引入型別別名，`NIL` 的位置寫 `null`。
	+ 參數 `O` 的值來自執行選項 `OptTestExecutor.Arg`，所有用例共用同一個引用。
		絕大多數用例用不到這個參數，因此不要把它當成每條用例各自的入參。
	+ 用例失敗時拋出例外，執行器據此判定失敗。

	用例的寫法有兩種，按長度與複用情況選擇：
]

#H[斷言][
	能用斷言的地方就用斷言：

	```cs
	var T = Assert.IsTrue;
	T(Add(1, 2) == 3);
	T(Add(4, 5) == 6, "期望 9");
	```

	不要手寫 `if(Add(1, 2) != 3){ throw new Exception("..."); }` 這樣的判斷。

	`Assert` 只有 `IsTrue` 一個成員，沒有斷言拋出例外的工具。
	`Assert.IsTrue`就這一樣就夠你大部分場景用了
	需要斷言某個調用會拋出指定型別的例外時，測試工程自己做一個小工具，
	倉庫中的慣例是各測試域自帶 `Chk.Throws<TErr>(Action)`。
	若暫時沒有這類工具，測試代碼就地寫 `try` 與 `catch`，再用 `T(false, "...")` 記錄失敗，
	不要因為缺少工具就放棄斷言。
]

#H[執行方式][
	默認情況下，同一層的子節點也就是同一批用例會並行執行，速度最快。
	需要控制執行次序時，節點提供兩個互相獨立的開關：

	+ `Node.Ordered = true` 讓本節點的直接子節點依序執行。
		這個開關不遞歸，子節點內部仍然可以並行。
		適用於先建立數據、再測、最後清理這類有先後關係的用例。
	+ `Node.NonParallelizable = true` 讓本節點及其整棵子樹都不參與並行。
		這個開關向下繼承，標在最外層即可。
		適用於搶佔共享資源的測試，例如同一張表、同一個文件、同一個端口。

	執行器還有一個全局開關。任何一處要求不並行，該處就不並行：

	```cs
	await new TreeTestExecutor().RunEtPrint(
		Mgr.TestNode
		, Opt: new OptTestExecutor{ IsParallel = false }
	);
	```

	`OptTestExecutor` 有三個公開欄位。
	`IsParallel` 表示是否並行，默認為真。
	`MaxDegreeOfParallelism` 表示最大並行度，默認為處理器數量。
	`Arg` 表示傳給每條用例的參數引用。
]


#H[測試涉及數據庫操作][
	被測函數會讀寫數據庫時，測試自己負責準備數據與清理數據。

	準備數據時，測試代碼先把測試數據插入數據庫。
	構造的測試數據要足夠獨特，避免與既有數據重複，否則斷言可能命中別的數據。

	清理數據時，測試代碼在測試結束後硬刪除插入的數據。
	不論測試成功還是失敗，這些數據都要刪除，因此清理動作放在 `finally` 塊中。

	此外，建立數據與清理數據這兩條用例要能被單獨重複執行，不要依賴上一輪留下的數據。
	多條用例會讀寫同一批數據時，測試代碼再給節點加 `NonParallelizable`，
	否則並行執行會互相干擾。
]


#H[AI 新增測試時的操作順序][
	你是 AI 時，用戶要求給某個類補測試，按下面的順序做：

]


#H[聲明與實現分離][
	用戶要求聲明與實現分離,
	測試代碼同樣適用這條規則。

	+ 函數的聲明寫在 `.cs` 文件，實現寫在 `.Impl.cs` 文件；
	+ 每個測試用例都寫成常態具名函數，不使用匿名函數；
	+ 聲明文件只保留 `partial` 函數聲明與註釋。

	範例如下。聲明文件：

	````cs
	File: MyDomains/Calculator/TestAdd.cs
	using Tsinswreng.CsTreeTest;

	namespace MyProj1.Test.MyDomains.Calculator;

	// 本文件只測 ICalculator.Add 這一個被測函數。
	public partial class TestCalculator {
		public partial void RegisterAdd(ITestNode Node);

		///把 Add 的用例掛到節點上
		public partial Task<nil> AddPositiveNumbers(obj? O);

		///正負數相加
		public partial Task<nil> AddPositiveAndNegativeNumbers(obj? O);
	}
	````

	實現文件：

	````cs
	File: MyDomains/Calculator/TestAdd.Impl.cs
	using Tsinswreng.CsTreeTest;

	namespace MyProj1.Test.MyDomains.Calculator;

	// 本文件只測 ICalculator.Add 這一個被測函數。
	public partial class TestCalculator {
		public partial void RegisterAdd(ITestNode Node) {
			var R = Node.MkRegister<TestCalculator>(
				typeof(ICalculator)// 被測類型
				,nameof(ICalculator.Add)// 被測函數名
				,"Add:"// 用例名前綴
			).Register;
			var T = Assert.IsTrue;

			R(nameof(AddPositiveNumbers), AddPositiveNumbers!);
			R(nameof(AddPositiveAndNegativeNumbers), AddPositiveAndNegativeNumbers!);
		}

		public partial async Task<nil> AddPositiveNumbers(obj? O){
			T(Calculator.Add(5, 3) == 8, "期望 8");
			T(Calculator.Add(6, 4) == 10, "期望 10");
			return NIL;
		}

		public partial async Task<nil> AddPositiveAndNegativeNumbers(obj? O){
			T(Calculator.Add(5, -3) == 2);
			return NIL;
		}
	}
	````

	具名用例的簽名固定為 `Task<nil> 函數名(obj? O)`。
	註冊時用 `nameof` 對齊用例名，讓函數名與報告中的用例名是同一個詞。
]

