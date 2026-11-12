#import "@local/tsinswreng-scriptorium:0.1.0": *
#show: _Show


#import "@preview/tsinswreng-auto-heading:0.1.0": auto-heading
#let H = auto-heading;
\-\-\-

name: tsinswreng-cstreetest

description: CsTreeTest測試框架寫法規範

\-\-\-

#H[適用範圍與版本前提][
	測試框架：自研的 `Tsinswreng.CsTreeTest`。
	本文按*本地源 `0.2.0-alpha`* 的 API 寫。

	*照抄之前先確認手頭工程用的是哪一代*，兩代混用編不過：

	+ `0.2.0-alpha`（本文規範的對象）：`Tester` 基類 ＋ `Init()` ＋ `MkRegister`。
	+ `0.1.1-alpha`: 已廢棄。兩代不兼容
]

#H[參考示例與現成代碼][
	同目錄下 `TestSample.typ` 是按 `0.1.1` 生成的舊樣本：
	*組織方式可參考，API 一律以本文為準*。

	倉庫內可編譯的現行示例：`TswgLib/CsTreeTest/proj/Samples/MyProj1.Test`。
	該示例的 `Program.cs` 註釋裏出現 `GetNodeByTesterType`、
	`GetNodesByTesteeFnName` 這兩個方法在庫中*並不存在*（只是註釋，所以能編），別照抄。
]

#H[寫法範式一覽][
	一個測試工程分這幾層，每層職責固定，不要越界：

	+ 入口 `Program.cs`：三步固定——備依賴來源、`Init()`、跑。
	+ 測試管理器 `XxxTestMgr.cs`：本工程的樹根，只掛測試類，不寫用例。
	+ 測試類主檔 `_TestXxx.cs`：一被測類一個，只取依賴並把各分片串起來，不寫用例。
	+ 分片 `Test<被測函數名>.cs`：一被測函數一個檔，只放這個函數的用例。
	+ 依賴來源 `Di.cs` ＋ `GlobalUsing.cs`：測試類用 `GetRSvc<T>()` 直接取被測對象。

	一句話記法：*管理器管樹，主檔管組裝，分片管用例，入口管時序。*

	幾條固定約定：

	+ 分片的註冊方法簽名固定為 `void Register<被測函數名>(ITestNode Node)`；
		主檔在 `Init()`（或舊入口 `RegisterTestsInto`）裏把 `TestNode`／`Node` 傳進去。
		這樣同一個分片在兩代裝配方式下都能用，遷移時分片可以一字不改。
	+ 測試類*不要寫建構子注入*：框架只 `new` 無參構造，不會替你把依賴塞進建構子。
		依賴一律走 `GetRSvc<T>()`（欄位初始化時取，或用例執行時取）。
	+ 用例失敗靠*拋例外*表示，不要吞例外、不要用返回值表示成敗。
	+ 一個被測函數的用例歸一個檔；一個被測類歸一個目錄。
]

#H[工程骨架][
	#H[依賴來源 `Di.cs` 與 `GlobalUsing.cs`][
		框架本身*不依賴任何依賴注入套件*，也不參與取依賴。
		每個測試工程自備這兩個檔：

		```cs
		File: Di.cs
		using Microsoft.Extensions.DependencyInjection;

		namespace MyProj1.Test;

		// 本測試工程的全局依賴來源。框架只負責 new 測試類，依賴由測試類自己來問本類。
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

		```cs
		File: GlobalUsing.cs
		// 讓測試檔直接寫 GetRSvc<T>()，不必帶 Di. 前綴。
		global using static MyProj1.Test.Di;
		```

		入口要引用微軟的依賴注入套件；框架不需要，所以引用放在測試工程自己的 csproj。
	]

	#H[測試管理器 `MyProj1TestMgr.cs`][
		繼承 `Tester`，重寫 `Init()`，只往樹上掛測試類：

		```cs
		File: MyProj1TestMgr.cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test;

		// 本工程的樹根。只掛測試類，不寫用例。
		public class MyProj1TestMgr : Tester{
			public static MyProj1TestMgr Inst = new();

			public override void Init(){
				// 根節點顯式命名，失敗路徑才可讀。
				TestNode.UniqName = "Tests";
				// 子節點由 AddTester 建，節點名默認取類型短名，即 "TestCalculator"。
				AddTester<TestCalculator>();
			}
		}
		```
	]

	#H[入口 `Program.cs`][
		```cs
		File: Program.cs
		using Microsoft.Extensions.DependencyInjection;
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test;

		public static class Program{
			public static async Task<int> Main(){
				// 1: 依賴來源必須先就緒——第 2 步的 Init() 會立刻 new 出測試類，
				//    而測試類在建欄位時就向 Di 取被測對象。
				Di.SvcProvider = new ServiceCollection()
					.AddSingleton<ICalculator, Calculator>()
					.BuildServiceProvider();

				// 2: 先給根節點，再 Init。
				var Mgr = MyProj1TestMgr.Inst;
				Mgr.TestNode = new TestNode();
				Mgr.Init();

				// 3: 跑。默認不因失敗而拋異常，成敗由入口自己判斷。
				var Summary = await new TreeTestExecutor().RunEtPrint(Mgr.TestNode);
				return Summary.Failed > 0 ? 1 : 0;
			}
		}
		```

		三步順序是硬約束：依賴來源在前、`Init()` 在中、跑在後。
		顛倒的症狀是 `InvalidOperationException`、或取到 `null` 之後在別處炸。

		CI 裏想讓失敗直接中斷，就傳 `ThrowOnFailed: true`：

		```cs
		await new TreeTestExecutor().RunEtPrint(Mgr.TestNode, ThrowOnFailed: true);
		```
	]
]

#H[測試類與分片骨架][
	#H[主檔 `_TestXxx.cs`][
		```cs
		File: MyDomains/Calculator/_TestCalculator.cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test.MyDomains.Calculator;

		// 主檔：只取依賴與串註冊，自己不寫用例。
		public partial class TestCalculator : Tester{
			// 依賴在欄位初始化時取。不要用建構子注入。
			readonly ICalculator Calculator = GetRSvc<ICalculator>();

			public override void Init(){
				// 分片拿到的是本測試類的節點。
				RegisterAdd(TestNode);
				RegisterTryIntDivide(TestNode);
			}
		}
		```

		每個被測函數的用例在各自的分片檔裏；新增一個被測函數，就在 `Init()` 多加一行。
	]

	#H[分片 `Test<被測函數名>.cs`][
		```cs
		File: MyDomains/Calculator/TestAdd.cs
		using Tsinswreng.CsTreeTest;

		namespace MyProj1.Test.MyDomains.Calculator;

		// 本檔只測 ICalculator.Add 這一個被測函數。
		public partial class TestCalculator{
			public void RegisterAdd(ITestNode Node){
				var R = Node.MkRegister<TestCalculator>(
					typeof(ICalculator)// 被測類型
					,nameof(ICalculator.Add)// 被測函數名，必須用 nameof
					,"Add:"// 用例名前綴，讓路徑成 Tests/TestCalculator/Add:正數相加
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

		*分片檔不要自己 new 個節點、也不要自己跑*：它只往給定的節點掛用例。
	]
]

#H[註冊用例：`MkRegister`][
	三個重載，按「已知多少元數據」挑：

	+ `Node.MkRegister<TestX>(typeof(IXxx), nameof(IXxx.Fn), "前綴")`：最常用，一個被測類型一個函數。
	+ `Node.MkRegister<TestX>([typeof(IXxx), typeof(IYyy)], [nameof(IXxx.A), nameof(IYyy.B)], "前綴")`：
		一個檔測多個被測函數時用；兩個列表要一一對齊。
	+ `Node.MkRegister(typeof(TestX), ..., "前綴")`：測試類類型運行時才知道時用。

	要點：

	+ 必須直接取 `.Register` 方法組：寫 `var R = Node.MkRegister<TestX>(...).Register;`。
		若先存註冊器、再另起一行 `Reg.Register(...)`，會報 CS0149（應輸入方法名稱）。
	+ 不給元數據時一個參數都別傳：寫 `MkRegister<TestX>()`；
		寫 `(null, null)` 會與另一個重載歧義（CS0121）。
	+ 元數據按*調用時*的欄位值快照，所以中途改 `UniqNamePrefix` 會影響後續用例，不影響已註冊的。
	+ 前綴是給人看的：失敗輸出是 `節點路徑/前綴+用例名`，一眼能看出哪個被測函數的哪條用例。
	+ 不用前綴時，用例名自己要全樹唯一，否則失敗路徑分不清是哪一條。

	不需要被測元數據的極簡場合，也可以直接在測試類上掛一條：

	```cs
	// 只掛一條用例、不記被測類型與函數名。
	var T = Assert.IsTrue;
	AddTestCase("健康檢查", async (O) => {
		T(GetRSvc<ICalculator>() is not null);
		return NIL;
	});
	```
]

#H[用例本體][
	用例函數的型別是 `Task<obj?> FnTest(obj? Arg)`。

	+ 一律 async；同步邏輯直接 `return NIL;`（工程沒帶類型別名檔時寫 `return null;`）。
	+ 參數 `O` 是 `OptTestExecutor.Arg`，*所有用例共用同一個引用*；
		幾乎用不到，不要拿它當每條用例各自的參數。
	+ 默認用匿名 lambda：短、就近可讀，能直接閉包捕獲欄位與局部變量。
	+ 用例很長、或要重用、或用戶要求聲明與實現分離時，改成常態具名函數，
		再 `R(nameof(MyCase), MyCase!)` 註冊；`!` 是因為 `Task<nil>` 與 `Task<obj?>` 的可空性不同。
	+ 不要在用例裏把例外吞掉；拋出來才算失敗。要斷言「應該拋某種例外」就自己寫檢查器。

	要跨用例共享狀態（例如建置數據後給後續用例用），用測試類欄位或閉包變量，
	並把該節點設成有序（見「並行與順序」一節），不要靠執行順序碰運氣。
]

#H[用例命名][
	用例名應當滿足：

	+ 在同一個測試類內易於辨認；
	+ 能看出測什麼行爲；
	+ 不要寫成含糊的 `Test1`、`Try`、`Temp`。

	有前綴時，前綴寫「被測函數名＋冒號」，用例名只寫行爲本身，例如
	`Add:` 配 `正數相加`、`TryIntDivide:` 配 `除數為零時回傳假`。
]

#H[斷言][
	能用斷言就用斷言：

	```cs
	var T = Assert.IsTrue;
	T(Add(1, 2) == 3);
	T(Add(4, 5) == 6, "期望 9");
	```

	避免自己寫 `if(Add(1,2) != 3){ throw new Exception("..."); }`。

	`Assert` 只有 `IsTrue(bool, str?)` 一個成員，*沒有* `Throws` 之類。
	要斷言「會拋某種例外」時自寫一個小工具（倉庫慣例是各測試域自帶 `Chk.Throws<TErr>(Action)`），
	或就地 `try`／`catch` 後 `T(false, "...")`；不要因為缺工具就放棄斷言。

	失敗消息寫清*期望值與實際值*，別只寫「失敗」。
]

#H[並行與順序][
	默認全並行：同一層的子節點（也就是同一批用例）會同時跑，速度最快。

	兩個開關互相獨立，別混用：

	+ `Node.Ordered = true`：本節點的直接子節點*依序*跑。不遞歸，子節點內部仍可並行。
		用於「先建置數據、再測、最後清理」這類有先後關係的用例。
	+ `Node.NonParallelizable = true`：本節點*及其整棵子樹*都不參與並行，向下繼承。
		用於搶佔共享資源（同一張表、同一個檔、同一個端口）的測試。
		標在最外層即可。

	全局總閘是執行選項，任一要求不並行就不並行：

	```cs
	await new TreeTestExecutor().RunEtPrint(
		Mgr.TestNode
		, Opt: new OptTestExecutor{ IsParallel = false }
	);
	```

	`OptTestExecutor` 的三個公開字段：`IsParallel`（默認真）、
	`MaxDegreeOfParallelism`（默認處理器數）、`Arg`（傳給每條用例的那個引用）。
]

#H[怎麼收編子程序集(csproj)測試][
	`0.2.0` 沒有 `TestMgr`、也沒有 `RegisterSubMgr`。
	收編下級測試工程的做法：上層管理器在 `Init()` 裏把下級管理器當*子測試類*掛上。

	```cs
	File: WindowsTestMgr.cs
	using Ngan.Dict.Core.Test;
	using Ngan.Dict.Local.Test;
	using Tsinswreng.CsTreeTest;

	namespace Ngan.Dict.Windows.Test;

	// 上層管理器：只收編下級管理器，不直接註冊下級的每個測試類。
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

	要點：

	+ 子節點由父方建，名默認取類型短名；想改名就用 `AddTester(new LocalTestMgr(), typeof(LocalTestMgr))` 前先建節點，或事後改 `UniqName`。
	+ 同一個管理器*實例只能掛一次*：已 `Inited` 的實例再掛會拋 `InvalidOperationException`。
		所以要嘛每層各自持 `static Inst`、只掛這一個實例，要嘛用泛型重載讓框架自己 `new`。
	+ 下級管理器也得是 `ITester`（通常同樣繼承 `Tester`），不能是裸的靜態類。
	+ 倉庫裏按 `0.1.1` 寫的收編（`DiEtTestMgr` ＋ `RegisterSubMgr`）暫時不動，等用戶拍板再遷。
]

#H[測試涉及數據庫操作的函數][
	要先自行把測試數據插入數據庫，注意構造的測試數據要足夠獨特、
	避免與其他已有數據重複；測試結束後（不管成功還是失敗）都要把插入的數據都硬刪除。

	不需要在每條用例都做一遍建置與清理：

	+ 把該節點設 `Node.Ordered = true`；
	+ 第一條用例建置數據，中間的用例跑斷言，最後一條用例清理數據；
	+ 清理要放在 `finally` 裏，避免中途失敗就留下垃圾；
	+ 建置與清理這兩條也要能被單獨重跑，不要依賴「前一輪的殘留」。

	多條用例會碰同一批數據時，再加 `NonParallelizable`，否則並行下互相踩。
]

#H[舊寫法（0.1.1）與遷移邊界][
	需要跟舊工程保持一致時，仍可走舊入口 `RegisterTestsInto`：

	```cs
	// 舊寫法：實作 ITester 的 RegisterTestsInto。0.2.0 仍支援，但已標 Obsolete。
	public partial class TestCalculator : ITester{
		readonly ICalculator Calculator = GetRSvc<ICalculator>();

		// 參數必須是可空的 ITestNode?；寫成非可空會 CS8767。
		public ITestNode RegisterTestsInto(ITestNode? Node){
			Node ??= new TestNode();
			RegisterAdd(Node);
			RegisterTryIntDivide(Node);
			return Node;
		}
	}
	```

	管理器一側的老式掛法（用 `NewTesterChild` 建節點再交出去）也還能用：

	```cs
	var node = TestNode.NewTesterChild(typeof(TestCalculator), nameof(TestCalculator));
	new TestCalculator().RegisterTestsInto(node);
	```

	注意：直接 `: ITester` 而不繼承 `Tester` 時，`TestNode`／`Inited`／`Init`
	用的是介面默認實作，取 `TestNode` 會拋 `NotSupportedException`，
	所以*不要用 `AddTester` 去掛這種測試類*。要混用就繼承 `Tester`。

	`0.1.1` 到 `0.2.0` 的對照：

	+ `DiEtTestMgr` ＋ `RegisterTester<T>()`：改成 `Tester` ＋ `AddTester<T>()`。
	+ `InitSvc(SvcColct, ...)`：刪掉；改成入口裏自己建容器並賦給 `Di.SvcProvider`。
	+ `RegisterSubMgr(下級)`：改成 `AddTester<下級管理器>()`。
	+ 建構子注入：改成 `GetRSvc<T>()`（欄位初始化或用例內）。
	+ `MkTestFnRegister`：改成 `MkRegister`（舊名仍可用）。
	+ `IsParallelRecursive`：改成 `NonParallelizable`，語義相同（為真即不並行）。

	*不要順手改舊檔*：倉庫裏上千處舊寫法仍在用舊 API，遷移要當成獨立任務、由用戶拍板範圍。
]

#H[AI 新增測試時的最小操作清單][
	如果你是 AI，當用戶要求「爲某個類補測試」時，按這個順序做：

	+ 先確認目標工程用的是哪一代 API：看它的 `XxxTestMgr.cs` 是繼承 `Tester` 還是 `DiEtTestMgr`。
	+ 找到對應模塊下最近的測試目錄。
	+ 新建 `_TestXxx.cs` 作爲主檔（新寫法 `: Tester` ＋ `override Init()`），
		再按被測函數新建 `Test<Fn>.cs`，各自寫 `Register<Fn>(ITestNode Node)`。
	+ 在最近的測試管理器補一行 `AddTester<TestXxx>()`（舊工程則按它原本的寫法補）。
	+ 只有新建測試工程時，才需要補 `Di.cs`、`GlobalUsing.cs`、`Program.cs`、csproj。
	+ 不看主入口，除非用戶明確要求。
	+ 動手前先把「這個工程是舊寫法、我只加檔不改既有檔」講清楚；有疑問先問，不要擅自遷移。
]

#H[常見編譯錯誤][
	+ CS0149（應輸入方法名稱）：把 `ITestFnRegister` 存進局部變量再調用。
		取 `.Register` 方法組即可。
	+ CS0121（調用歧義）：`MkRegister<TestX>(null, null)`。不給元數據就一個參數都別傳。
	+ CS8767：實作 `RegisterTestsInto` 時參數寫成非可空。介面是可空的，照抄 `ITestNode? Node`。
	+ 具名用例轉 `FnTest` 報可空性不符：`R(nameof(X), X!)`，加 `!`。
	+ 執行時 `InvalidOperationException`／`NotSupportedException`：
		多半是 `Di.SvcProvider` 沒先賦值、或把 `: ITester` 的舊寫法測試類交給 `AddTester`。
	+ 用例名重複導致路徑分不清：給 `MkRegister` 加前綴，或改名。
]

#H[聲明與實現分離][
	當用戶要求你聲明與實現分離時（測試代碼同樣適用）：

	+ 只在 `.Impl.cs` 裏實現函數與註冊用例；
	+ 每個測試用例函數用常態具名函數聲明和實現、不用匿名函數；
	+ 聲明檔只留 `partial` 函數聲明與註釋。

	例：

	````cs
	File: MyDomains/Calculator/TestAdd.cs
	using Tsinswreng.CsTreeTest;

	namespace MyProj1.Test.MyDomains.Calculator;
	// 本檔只測 ICalculator.Add 這一個被測函數。
	public partial class TestCalculator {
		public partial void RegisterAdd(ITestNode Node);

		///把 Add 的用例掛到節點上
		public partial Task<nil> AddPositiveNumbers(obj? O);

		///正負數相加
		public partial Task<nil> AddPositiveAndNegativeNumbers(obj? O);
	}
	````

	````cs
	File: MyDomains/Calculator/TestAdd.Impl.cs
	using Tsinswreng.CsTreeTest;

	namespace MyProj1.Test.MyDomains.Calculator;
	// 本檔只測 ICalculator.Add 這一個被測函數。
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

	具名用例的簽名固定為 `Task<nil> 名字(obj? O)`，
	註冊時用 `nameof` 對齊用例名，讓「函數名」與「報告裏的用例名」是同一個詞。
]

#H[總結注意事項和禁止事項][
	+ 一個測試類通常對應一個被測類；不同測試類放在不同目錄。
	+ 測試類用 `partial class`：以 `_TestXxx.cs` 作主檔，只負責組裝；
		每個 `Test<Fn>.cs` 只主要測一個被測函數。
	+ 每個測試 csproj 都要有測試管理器；上層管理器只收編下級管理器，不直接註冊下級的各個測試類。
	+ 註冊測試時，用 `nameof(...)` 指明被測函數，且用例名必須能辨認所測行爲。
	+ 能使用 `Assert` 時，不要手動以 `if` 加 `throw` 實現斷言。
	+ 依賴一律走 `GetRSvc<T>()`；不要用建構子注入，框架不會傳參數給你。
	+ 涉及數據庫時，測試數據必須唯一，並確保無論測試結果如何都會硬刪除；
		可用有序節點集中完成建置與清理，必要時再禁並行。
	+ 禁止把不同 API 的測試用例寫進同一個文件。
	+ 禁止使用含糊的用例名，如 `Test1`、`Try`、`Temp`。
	+ 禁止未經用戶要求就把 `0.1.1` 舊寫法的測試檔改寫成新寫法。
	+ 禁止照抄 `GetNodeByTesterType`、`GetNodesByTesteeFnName`、`RegisterSubMgr`、
		`DiEtTestMgr`、`InitSvc` 這些在 `0.2.0` 已不存在的東西。
]
