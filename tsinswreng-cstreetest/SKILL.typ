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
		這一代表現為 `Tester` 基類、`Init()` 方法與 `MkRegister` 方法。
	+ `0.1.1-alpha` 是 NuGet 上的版本，倉庫中大量既有測試文件按這一版寫成。
		這一代表現為 `DiEtTestMgr` 基類、`InitSvc` 方法與 `MkTestFnRegister` 方法，
		被測對象通過建構子注入取得。

	`0.2.0-alpha` 保留了幾個舊名字，讀者需要分清這些名字的性質：

	+ `MkTestFnRegister` 仍然可以編譯，它的實現直接轉發給 `MkRegister`。
		新代碼一律寫 `MkRegister`。
	+ `ITester.RegisterTestsInto` 已標記為 `Obsolete`，但仍然可用。
		這條路徑是舊測試類的入口，新測試類改用 `Init()`。
	+ 舊屬性 `IsParallelRecursive` 已改名為 `NonParallelizable`，語義不變。
		兩個名字都表示同一個規則：值為真時，本節點及其全部子節點不參與並行。
		舊名字的字面意思與實際語義相反，因此改名的時候不能只換字面。

	倉庫中按 `0.1.1-alpha` 寫成的測試文件仍然使用舊 API。
	*這些文件不要為了統一風格而改寫*，因為改寫會產生大量與當前需求無關的差異。
	新寫的測試使用新寫法；需要遷移舊文件時，由用戶指定遷移範圍。
]

#H[可參考的現成代碼][
	同目錄下的 `TestSample.typ` 是按 `0.1.1-alpha` 生成的舊樣本。
	樣本中的文件劃分方式仍然可以參考，樣本中的 API 則以本文為準。

	倉庫內可編譯的現行示例位於 `TswgLib/CsTreeTest/proj/Samples/MyProj1.Test`。
	該示例的 `Program.cs` 註釋中出現了 `GetNodeByTesterType` 與 `GetNodesByTesteeFnName` 兩個方法。
	這兩個方法在庫中沒有定義，只因寫在註釋裏才沒有影響編譯。
	讀者讀到這兩個名字時不要照抄。
]

#H[範式總覽][
	一個測試工程由四層組成，每一層只做一件事：

	+ 入口 `Program.cs` 負責時序。入口先備好依賴來源，再初始化測試管理器，最後執行測試。
	+ 測試管理器 `XxxTestMgr.cs` 負責管理測試樹。管理器持有整棵樹的根節點，
		把各測試類掛到根節點下，自身不寫用例。
	+ 測試類主檔 `_TestXxx.cs` 負責組裝。一個被測類對應一個測試類，
		主檔從依賴來源取出被測對象，再把各分片註冊的用例串起來，自身不寫用例。
	+ 分片 `Test<被測函數名>.cs` 負責用例。一個被測函數對應一個文件，
		分片只往給定的節點上掛這個函數的用例。

	把四層的職責連起來看：管理器管理測試樹的骨架，主檔把分片接到骨架上，
	分片提供具體用例，入口決定三者的執行時機。

	四層之外，測試工程還需要一個依賴來源 `Di.cs`。
	框架只用無參建構子實例化測試類，不參與取依賴，
	所以測試類需要的被測對象由測試類自己向 `Di` 索取。

	除結構之外，本文還規定幾條寫法約定：

	+ 分片的註冊方法簽名固定為 `void Register<被測函數名>(ITestNode Node)`。
		主檔調用這些方法時，把測試類自己的節點傳進去。
		這樣同一個分片既能被 `Init()` 裝配，也能被舊入口 `RegisterTestsInto` 裝配，
		遷移時分片的內容不必改動。
	+ 測試類不使用建構子注入。框架實例化測試類時不傳參數，
		依賴一律通過 `GetRSvc<T>()` 取得。
	+ 用例失敗以拋出例外表示。用例內部不要把例外吞掉，也不要用返回值表示成敗。
	+ 一個被測函數的用例放在一個文件裏，一個被測類的測試放在一個目錄裏。
]

#H[工程級骨架][
	#H[依賴來源][
		框架不依賴任何依賴注入套件，也不負責取依賴。
		因此每個測試工程自備一個靜態類 `Di`。入口把服務提供器賦給這個類，
		測試類再通過這個類取出被測對象。

		```cs
		File: Di.cs
		using Microsoft.Extensions.DependencyInjection;

		namespace MyProj1.Test;

		// 本測試工程的依賴來源。
		// 框架只負責實例化測試類，被測對象由測試類向本類索取。
		public static class Di{
			public static IServiceProvider SvcProvider{
				get{ return field ?? throw new InvalidOperationException("Di.SvcProvider has not been initialized."); }
				set{ field = value ?? throw new ArgumentNullException(nameof(value)); }
			}
			public static T GetRSvc<T>() where T:class{
				return SvcProvider.GetRequiredService<T>();
			}
		}
		```

		為了讓測試代碼直接寫 `GetRSvc<T>()` 而不必帶上 `Di.` 前綴，
		測試工程再加一個全局 using：

		```cs
		File: GlobalUsing.cs
		global using static MyProj1.Test.Di;
		```

		入口與 `Di` 會用到微軟的依賴注入套件，所以測試工程的 csproj 要引用
		`Microsoft.Extensions.DependencyInjection`。框架本身不需要這個套件。
	]

	#H[測試管理器][
		管理器繼承 `Tester`，重寫 `Init()`，只往測試樹上掛測試類：

		```cs
		File: MyProj1TestMgr.cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test;

		// 本工程的測試樹。只掛測試類，不寫用例。
		public class MyProj1TestMgr : Tester{
			public static MyProj1TestMgr Inst = new();

			public override void Init(){
				// 根節點顯式命名，失敗時打印的路徑才可讀。
				TestNode.UniqName = "Tests";
				// 子節點由 AddTester 建立，節點名默認取類型短名，即 TestCalculator。
				AddTester<TestCalculator>();
			}
		}
		```

		測試類的節點由管理器建立。管理器不必先實例化測試類，也不必手動建立節點。
	]

	#H[入口][
		入口固定三步，順序不可調換：

		```cs
		File: Program.cs
		using Microsoft.Extensions.DependencyInjection;
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test;

		public static class Program{
			public static async Task<int> Main(){
				// 第一步：備好依賴來源。
				// 這一步必須在第二步之前，因為第二步會立刻實例化測試類，
				// 而測試類在建欄位時就向 Di 索取被測對象。
				Di.SvcProvider = new ServiceCollection()
					.AddSingleton<ICalculator, Calculator>()
					.BuildServiceProvider();

				// 第二步：先給根節點，再初始化管理器。
				var Mgr = MyProj1TestMgr.Inst;
				Mgr.TestNode = new TestNode();
				Mgr.Init();

				// 第三步：執行。
				// 默認情況下，執行器不因用例失敗而拋出例外，成敗由入口自己判斷。
				var Summary = await new TreeTestExecutor().RunEtPrint(Mgr.TestNode);
				return Summary.Failed > 0 ? 1 : 0;
			}
		}
		```

		三步的順序顛倒會出現兩種症狀。
		依賴來源的賦值晚於 `Init()` 時，測試類在建構欄位時拋出 `InvalidOperationException`。
		根節點的賦值晚於 `Init()` 時，管理器往空引用上掛節點，同樣拋出例外。

		持續集成環境需要失敗即中斷時，入口給執行器傳 `ThrowOnFailed`：

		```cs
		await new TreeTestExecutor().RunEtPrint(Mgr.TestNode, ThrowOnFailed: true);
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
			// 被測對象在欄位初始化時取得。
			readonly ICalculator Calculator = GetRSvc<ICalculator>();

			public override void Init(){
				// 分片拿到的是本測試類的節點。
				RegisterAdd(TestNode);
				RegisterTryIntDivide(TestNode);
			}
		}
		```

		每個被測函數的用例寫在各自的分片文件裏。
		因此新增一個被測函數的測試時，主檔只加一行 `Register<函數名>(TestNode)`。
	]

	#H[分片][
		```cs
		File: MyDomains/Calculator/TestAdd.cs
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

		前綴 `Add:` 會拼在用例名之前，所以第一條用例在報告中的路徑是
		`Tests/TestCalculator/Add:正數相加`。
		讀者從路徑就能看出失敗屬於哪個被測函數的哪條用例。

		分片只把用例掛到主檔交給它的節點上。
	]
]

#H[註冊用例][
	`MkRegister` 有三個重載，按已知的元數據多少選擇：

	+ `Node.MkRegister<TestX>(typeof(IXxx), nameof(IXxx.Fn), "前綴")`：
		適用於一個被測類型、一個被測函數。這是最常用的一種。
	+ `Node.MkRegister<TestX>(類型列表, 函數名列表, "前綴")`：
		適用於一個文件測多個被測函數。兩個列表按順序一一對應。
	+ `Node.MkRegister(typeof(TestX), 類型列表, 函數名列表, "前綴")`：
		適用於測試類的型別在運行時才確定的場合。

	註冊時有五個要點：

	1. 必須直接取 `.Register` 方法組，寫成 `var R = Node.MkRegister<TestX>(...).Register;`。
		若先把註冊器存進局部變量，再另起一行調用 `Register`，編譯器報 CS0149。
	2. 不提供元數據時，一個參數都不要寫。
		寫成 `MkRegister<TestX>()` 可以編譯；寫成 `MkRegister<TestX>(null, null)`
		則與另一個重載歧義，編譯器報 CS0121。
	3. 元數據按調用時的欄位值快照。
		因此中途修改 `UniqNamePrefix` 只影響後續註冊的用例，不影響已經註冊的用例。
	4. 前綴讓失敗路徑可讀。用例名本身仍然要保持全樹唯一，
		否則報告中兩條用例的路徑相同，讀者無法區分。
	5. 用例名要能看出所測行為，不要寫成 `Test1`、`Try`、`Temp` 這類含糊的名字。

	若某個場合完全不需要記錄被測型別與函數名，也可以直接把用例掛到測試類上：

	```cs
	// 只掛一條用例，不記錄被測型別與被測函數名。
	var T = Assert.IsTrue;
	AddTestCase("健康檢查", async (O) => {
		T(GetRSvc<ICalculator>() is not null);
		return NIL;
	});
	```
]

#H[用例本體][
	用例函數的型別是 `Task<obj?> FnTest(obj? Arg)`。這個型別決定了三件事：

	+ 用例一律是異步的。純同步的邏輯直接返回 `NIL` 即可。
		工程若沒有引入型別別名，`NIL` 的位置寫 `null`。
	+ 參數 `O` 的值來自執行選項 `OptTestExecutor.Arg`，所有用例共用同一個引用。
		絕大多數用例用不到這個參數，因此不要把它當成每條用例各自的入參。
	+ 用例失敗時拋出例外，執行器據此判定失敗。

	用例的寫法有兩種，按長度與複用情況選擇：

	+ 默認使用匿名函數。這種寫法短，能就地捕獲主檔的欄位與局部變量。
	+ 用例較長、需要複用，或用戶要求聲明與實現分離時，改成常態具名函數，
		註冊時寫 `R(nameof(MyCase), MyCase!)`。
		`!` 不可省，因為 `Task<nil>` 與 `Task<obj?>` 的可空性不同。

	用例之間需要共享狀態時，測試代碼把狀態放在測試類的欄位或閉包變量裏，
	同時把該節點設為有序執行。讀者不要依賴並行執行下的偶然次序。
]

#H[用例命名][
	用例名應當滿足三個條件：

	+ 在同一個測試類內易於辨認；
	+ 能看出測的是什麼行為；
	+ 不用含糊的 `Test1`、`Try`、`Temp` 之類的名字。

	使用前綴時，前綴寫被測函數名加冒號，用例名只寫行為本身。
	例如測 `Add` 的用例寫成前綴 `Add:` 加用例名 `正數相加`。
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
	需要斷言某個調用會拋出指定型別的例外時，測試工程自己做一個小工具，
	倉庫中的慣例是各測試域自帶 `Chk.Throws<TErr>(Action)`。
	若暫時沒有這類工具，測試代碼就地寫 `try` 與 `catch`，再用 `T(false, "...")` 記錄失敗，
	不要因為缺少工具就放棄斷言。

	失敗消息要寫清期望值與實際值。只寫「失敗」的消息無法幫助定位問題。
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

#H[收編下級測試工程][
	`0.2.0-alpha` 沒有 `TestMgr` 型別，也沒有 `RegisterSubMgr` 方法。
	要收編下級測試工程，上層管理器在 `Init()` 裏把下級管理器當作子測試類掛上：

	```cs
	File: WindowsTestMgr.cs
	using Ngan.Dict.Core.Test;
	using Ngan.Dict.Local.Test;
	using Tsinswreng.CsTreeTest;

	namespace Ngan.Dict.Windows.Test;

	// 上層管理器只收編下級管理器，不直接註冊下級的每個測試類。
	public class WindowsTestMgr : Tester{
		public static WindowsTestMgr Inst = new();

		public override void Init(){
			TestNode.UniqName = "Tests";
			AddTester<LocalTestMgr>();
			AddTester<CoreTestMgr>();
			AddTester<TestSvcTokenStorage>();
		}
	}
	```

	收編時要注意三點：

	1. 子節點由父方建立，節點名默認取型別短名。
		需要自訂節點名時，父方先建立節點並賦值給子方的 `TestNode`，再調用子方的 `Init()`。
	2. 同一個管理器實例只能掛載一次。
		已經初始化過的實例再次掛載會拋出 `InvalidOperationException`。
		因此每層各自持有 `static Inst` 並只掛這一個實例，或者改用泛型重載讓框架自行實例化。
	3. 下級管理器也必須實作 `ITester`，通常同樣繼承 `Tester`。靜態類無法參與收編。

	倉庫中按 `0.1.1-alpha` 寫成的收編仍在使用 `DiEtTestMgr` 與 `RegisterSubMgr`。
	這部分代碼暫時不動，等用戶決定遷移範圍。
]

#H[測試涉及數據庫操作][
	被測函數會讀寫數據庫時，測試自己負責準備數據與清理數據。

	準備數據時，測試代碼先把測試數據插入數據庫。
	構造的測試數據要足夠獨特，避免與既有數據重複，否則斷言可能命中別的數據。

	清理數據時，測試代碼在測試結束後硬刪除插入的數據。
	不論測試成功還是失敗，這些數據都要刪除，因此清理動作放在 `finally` 塊中。

	不需要在每條用例裏都做一遍建立與清理。更經濟的做法是把這批用例組織到同一個節點下：

	1. 把該節點設為 `Node.Ordered = true`；
	2. 第一條用例插入數據；
	3. 中間的用例執行斷言；
	4. 最後一條用例清理數據。

	此外，建立數據與清理數據這兩條用例要能被單獨重複執行，不要依賴上一輪留下的數據。
	多條用例會讀寫同一批數據時，測試代碼再給節點加 `NonParallelizable`，
	否則並行執行會互相干擾。
]

#H[舊寫法與遷移邊界][
	需要與舊工程保持一致時，測試類仍可走舊入口 `RegisterTestsInto`：

	```cs
	// 舊寫法：實作 ITester 的 RegisterTestsInto。
	// 0.2.0-alpha 仍然支援這條路徑，但已標記為 Obsolete。
	public partial class TestCalculator : ITester{
		readonly ICalculator Calculator = GetRSvc<ICalculator>();

		// 參數必須是可空的 ITestNode?。寫成不可空會報 CS8767。
		public ITestNode RegisterTestsInto(ITestNode? Node){
			Node ??= new TestNode();
			RegisterAdd(Node);
			RegisterTryIntDivide(Node);
			return Node;
		}
	}
	```

	管理器一側的老式掛法也仍然可用。管理器先建立測試類節點，再把節點交給測試類：

	```cs
	var node = TestNode.NewTesterChild(typeof(TestCalculator), nameof(TestCalculator));
	new TestCalculator().RegisterTestsInto(node);
	```

	需要注意的是，直接實作 `ITester` 而不繼承 `Tester` 的測試類，
	`TestNode`、`Inited`、`Init` 三個成員用的是介面的默認實作。
	這類測試類讀取 `TestNode` 時拋出 `NotSupportedException`，
	因此不能把它交給 `AddTester` 掛載。需要混用兩種裝配方式時，測試類要繼承 `Tester`。

	從 `0.1.1-alpha` 遷移到 `0.2.0-alpha` 時，按下面的對照逐項替換：

	+ `DiEtTestMgr` 與 `RegisterTester<T>()` 換成 `Tester` 與 `AddTester<T>()`。
	+ `InitSvc(SvcColct, ...)` 整行刪除，改由入口建立容器並賦給 `Di.SvcProvider`。
	+ `RegisterSubMgr(下級)` 換成 `AddTester<下級管理器>()`。
	+ 建構子注入換成 `GetRSvc<T>()`。取值位置可以是欄位初始化，也可以是用例內部。
	+ `MkTestFnRegister` 換成 `MkRegister`。舊名字仍然可用。
	+ `IsParallelRecursive` 換成 `NonParallelizable`。兩個名字的語義相同。

	倉庫中仍有大量舊寫法在使用舊 API。
	遷移要做成一項獨立任務，範圍由用戶決定。
	讀者不要在看別的問題時順手改寫舊文件。
]

#H[AI 新增測試時的操作順序][
	你是 AI 時，用戶要求給某個類補測試，按下面的順序做：

	1. 先確認目標工程用的是哪一代 API。
		判斷方法是看工程的 `XxxTestMgr.cs` 繼承 `Tester` 還是 `DiEtTestMgr`。
	2. 找到對應模塊下最近的測試目錄。
	3. 建立主檔 `_TestXxx.cs`。新寫法讓主檔繼承 `Tester` 並重寫 `Init()`。
	4. 按被測函數建立分片 `Test<函數名>.cs`。
		每個分片寫一個 `Register<函數名>(ITestNode Node)` 方法。
	5. 在最近的測試管理器裏補一行 `AddTester<TestXxx>()`。
		工程屬於舊寫法時，按該工程原有的方式補。
	6. 只有建立新的測試工程時，才需要補 `Di.cs`、`GlobalUsing.cs`、`Program.cs` 與 csproj。
	7. 不動主入口，除非用戶明確要求。

	動手之前，先向用戶說清目標工程屬於哪一代寫法，以及本次只新增文件、不改既有文件。
	遇到本文沒有覆蓋的情況，先問用戶，不要自行遷移代際。
]

#H[常見編譯錯誤][
	+ 編譯器報 CS0149「應輸入方法名稱」。
		原因是把 `ITestFnRegister` 存進局部變量後再調用 `Register`。
		改法是直接取方法組，寫成 `var R = Node.MkRegister<TestX>(...).Register;`。
	+ 編譯器報 CS0121「調用歧義」。
		原因是寫了 `MkRegister<TestX>(null, null)`。
		改法是不提供元數據時一個參數都不寫。
	+ 編譯器報 CS8767。
		原因是實作 `RegisterTestsInto` 時把參數寫成不可空。
		改法是照介面寫成 `ITestNode? Node`。
	+ 註冊具名用例時報可空性不符。
		原因是用例函數的型別是 `Task<nil>`，而 `FnTest` 的型別是 `Task<obj?>`。
		改法是加 `!`，寫成 `R(nameof(X), X!)`。
	+ 執行時拋出 `InvalidOperationException`。
		原因是 `Di.SvcProvider` 尚未賦值，或同一個管理器實例被掛載了兩次。
		改法是按入口三步的順序裝配，並保證一個實例只掛一次。
	+ 執行時拋出 `NotSupportedException`。
		原因是被交給 `AddTester` 的測試類只實作了舊入口。
		改法是讓該測試類繼承 `Tester`，或改用舊式掛法。
	+ 報告中兩條用例的路徑相同。
		原因是用例名重複。
		改法是給 `MkRegister` 加前綴，或修改用例名。
]

#H[聲明與實現分離][
	用戶要求聲明與實現分離時，測試代碼同樣適用這條規則：

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

#H[總結][
	下面這些規則是寫測試時的底線。

	+ 一個測試類通常對應一個被測類，不同測試類放在不同目錄。
	+ 測試類用 `partial class`。主檔以 `_TestXxx.cs` 命名，只負責組裝；
		每個分片文件只主要測一個被測函數。
	+ 每個測試 csproj 都要有一個測試管理器。
		上層管理器只收編下級管理器，不直接註冊下級的各個測試類。
	+ 註冊用例時，用 `nameof` 指明被測函數，並且用例名要能辨認所測行為。
	+ 能使用 `Assert` 時，不要手動寫 `if` 加 `throw` 的斷言。
	+ 依賴一律通過 `GetRSvc<T>()` 取得。
		框架實例化測試類時不傳參數，因此不要使用建構子注入。
	+ 測試涉及數據庫時，測試數據必須唯一，並且不論測試成敗都硬刪除。
		這批用例可以設為有序，集中完成建立與清理；必要時再禁止並行。
	+ 不要把不同被測函數的用例寫進同一個文件。
	+ 不要使用 `Test1`、`Try`、`Temp` 這類含糊的用例名。
	+ 不要未經用戶要求就把 `0.1.1-alpha` 舊寫法的測試文件改寫成新寫法。
	+ 庫的 README 與示例註釋中提到的 `GetNodeByTesterType`、`GetNodesByTesteeFnName`、
		`RegisterSubMgr`、`DiEtTestMgr`、`InitSvc` 在 `0.2.0-alpha` 中沒有定義，讀者不要照抄。
]
