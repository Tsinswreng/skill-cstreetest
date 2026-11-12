---

name: tsinswreng-cstreetest

description: CsTreeTest測試框架寫法規範

---

## 版本前提

本skill針對`0.2.0-alpha`版本, `0.1.1-alpha` 已廢棄, 兩版不兼容

## 工程骨架

### 程序集入口

程序集入口的職責只有建立根節點與掛上組裝器：

`MyProj1Test.cs`

```cs

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
		//欲再註冊其他Tester則繼續寫 this.AddTester<Xxx>();
	}
}
```

### exe 入口

exe 入口放在另一個工程，固定三步，順序不可調換：

```cs
using Tsinswreng.CsTreeTest;
namespace MyProj1.Test;
public static class Program{
	public static async Task<int> Main(){
		var Tree = MyProj1Test.MkTree();
		var Summary = await new TreeTestExecutor().RunEtPrint(Tree);
		return Summary.Failed > 0 ? 1 : 0;
	}
}
```

## 測試類與分片

### 主檔

partial類主文件入口 命名規則:

```cs
被測類名+"/"+"_Test"+被測類名+".cs"
```

`MyDomains/Calculator/_TestCalculator.cs`

```cs
using Tsinswreng.CsTreeTest;

namespace MyProj1.Test.MyDomains.Calculator;

// 主檔只做兩件事：取被測對象，把各分片串起來。
public partial class TestCalculator : Tester{
	//不要寫多餘的沒必要的修飾符 如readonly 之類, 保持更少的代碼字符數
	ICalculator Calculator = Di.GetRSvc<ICalculator>();

	public override void Init(){
		// 分片直接往本測試類的節點上掛用例。
		RegisterAdd();
		RegisterTryIntDivide();
	}
}
```

### 分片

每個分片只負責測一個函數。 文件名不用`_`開頭 `MyDomains/Calculator/TestAdd.cs`

```cs
using Tsinswreng.CsTreeTest;

namespace MyProj1.Test.MyDomains.Calculator;

// 本文件只測 ICalculator.Add 這一個被測函數。
public partial class TestCalculator{
	void RegisterAdd(){
		var T = Assert.IsTrue;

		this.AddTestCase("Add_PositiveNumbers_Sum", async (O) => {
			T(Calculator.Add(5, 3) == 8);
			T(Calculator.Add(6, 4) == 10);
			return NIL;
		});

		this.AddTestCase("Add_PositiveAndNegative_Sum", async (O) => {
			var Sum = Calculator.Add(5, -3);
			T(Sum == 2, $"期望 2，實際 {Sum}");
			return NIL;
		});
	}
}
```

## 用例本體

用例函數的型別是 `Task<obj?> FnTest(obj? Arg)`。這個型別決定了三件事：

1. 用例一律是異步的。純同步的邏輯直接返回 `NIL` 即可。 工程若沒有引入型別別名，`NIL` 的位置寫 `null`。
2. 參數 `O` 目前用不到。留作擴展
3. 若用例拋出異常則執行器據此判定失敗。
4. `Assert.IsTrue`斷言失敗時即拋異常

用例可以寫成匿名函數，也可以寫成常態具名函數。 具名函數用 `this.AddTestCase(nameof(MyCase), MyCase!)` 註冊， `!` 不可省，因為 `Task<nil>` 與 `Task<obj?>` 的可空性不同。

## 斷言

能用斷言的地方就用斷言

```cs
var T = Assert.IsTrue;
T(Add(1, 2) == 3);
T(Add(4, 5) == 6, "期望 9");
```

不要手寫 `if(Add(1, 2) != 3){ throw new Exception("..."); }` 這樣的判斷。

`Assert` 只有 `IsTrue` 一個成員，沒有斷言拋出例外的工具。 `Assert.IsTrue`就這一樣就夠你大部分場景用了 需要斷言某個調用會拋出指定型別的例外時，測試工程自己做一個小工具， 倉庫中的慣例是各測試域自帶 `Chk.Throws<TErr>(Action)`。 若暫時沒有這類工具，測試代碼就地寫 `try` 與 `catch`，再用 `T(false, "...")` 記錄失敗， 不要因為缺少工具就放棄斷言。

## 執行方式

默認情況下，同一層的子節點也就是同一批用例會並行執行，速度最快。 需要控制執行次序時，節點提供兩個互相獨立的開關：

1. `Node.Ordered = true` 讓本節點的直接子節點依序執行。 這個開關不遞歸，子節點內部仍然可以並行。 適用於先建立數據、再測、最後清理這類有先後關係的用例。
2. `Node.NonParallelizable = true` 讓本節點及其整棵子樹都不參與並行。 這個開關向下繼承，標在最外層即可。 適用於搶佔共享資源的測試，例如同一張表、同一個文件、同一個端口。

執行器還有一個全局開關。任何一處要求不並行，該處就不並行：

```cs
await new TreeTestExecutor().RunEtPrint(
	Tree
	, Opt: new OptTestExecutor{ IsParallel = false }
);
```

`OptTestExecutor` 有三個公開欄位。 `IsParallel` 表示是否並行，默認為真。 `MaxDegreeOfParallelism` 表示最大並行度，默認為處理器數量。 `Arg` 表示傳給每條用例的參數引用。

## 測試涉及數據庫操作時

被測函數會讀寫數據庫時，測試自己負責隔離數據。

常見做法: 每套測試用例自己各自準備種子數據, 先把種子數據插入數據庫, 然後測試並斷言, 最後無論測試通過與否 都清除自己寫入的種子數據

準備數據時，測試代碼先把測試數據插入數據庫。 構造的測試數據要足夠獨特, 避免與既有數據重複, 否則斷言可能命中別的數據。

清理數據時, 測試代碼在測試結束後硬刪除插入的數據。 不論測試成功還是失敗, 這些數據都要刪除, 因此清理動作放在 `finally` 塊中。

此外，建立數據與清理數據這兩條用例要能被單獨重複執行，不要依賴上一輪留下的數據。 多條用例會讀寫同一批數據時，測試代碼再給節點加 `NonParallelizable`， 否則並行執行會互相干擾。

## 聲明與實現分離

用戶要求聲明與實現分離, 測試代碼同樣適用這條規則。

1. 函數的聲明寫在 `.cs` 文件，實現寫在 `.Impl.cs` 文件；
2. 每個測試用例都寫成常態具名函數，不使用匿名函數；
3. 聲明文件只保留 `partial` 函數聲明與註釋。

範例如下。聲明文件：

```cs
File: MyDomains/Calculator/TestAdd.cs
using Tsinswreng.CsTreeTest;

namespace MyProj1.Test.MyDomains.Calculator;

// 本文件只測 ICalculator.Add 這一個被測函數。
public partial class TestCalculator {
	public partial void RegisterAdd();

	///兩個正數相加
	public partial Task<nil> Add_PositiveNumbers_Sum(obj? O);

	///正數與負數相加
	public partial Task<nil> Add_PositiveAndNegative_Sum(obj? O);
}
```

實現文件：

```cs
File: MyDomains/Calculator/TestAdd.Impl.cs
using Tsinswreng.CsTreeTest;

namespace MyProj1.Test.MyDomains.Calculator;

// 本文件只測 ICalculator.Add 這一個被測函數。
public partial class TestCalculator {
	public partial void RegisterAdd() {
		this.AddTestCase(nameof(Add_PositiveNumbers_Sum), Add_PositiveNumbers_Sum!);
		this.AddTestCase(nameof(Add_PositiveAndNegative_Sum), Add_PositiveAndNegative_Sum!);
	}

	public partial async Task<nil> Add_PositiveNumbers_Sum(obj? O){
		var T = Assert.IsTrue;
		T(Calculator.Add(5, 3) == 8, "期望 8");
		T(Calculator.Add(6, 4) == 10, "期望 10");
		return NIL;
	}

	public partial async Task<nil> Add_PositiveAndNegative_Sum(obj? O){
		var T = Assert.IsTrue;
		T(Calculator.Add(5, -3) == 2);
		return NIL;
	}
}
```

具名用例的簽名固定為 `Task<nil> 函數名(obj? O)`。 註冊時用 `nameof` 對齊用例名，讓函數名與報告中的用例名是同一個詞。
